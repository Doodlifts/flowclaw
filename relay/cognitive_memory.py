"""
cognitive_memory.py — Cognitive Memory Engine for FlowClaw

Implements the cognitive memory architecture:
- Four memory types (episodic, semantic, procedural, self-model)
- Molecular bonds for O(k) retrieval
- Importance scoring and biological decay
- Dream cycle consolidation
- Memory promotion (episodic patterns → semantic facts)
- Selective on-chain commitment

Architecture inspired by:
- Stanford Generative Agents (Park et al. 2023)
- CoALA cognitive architecture
- ByteDance Mole-Syn molecular reasoning
- Flow blockchain: Cadence resources, scheduled transactions, XChaCha20 encryption
"""

import time
import math
import hashlib
import logging
import json
from typing import Dict, List, Optional, Tuple, Set
from dataclasses import dataclass, field
from enum import IntEnum
from collections import defaultdict


# -----------------------------------------------------------------------
# Memory Types (from cognitive science / CoALA)
# -----------------------------------------------------------------------
class MemoryType(IntEnum):
    EPISODIC = 0    # "I did X at time T" — events, conversations, experiences
    SEMANTIC = 1    # "X means Y" — learned facts, knowledge
    PROCEDURAL = 2  # "To do X, do Y then Z" — skills, workflows
    SELF_MODEL = 3  # "I am an agent who..." — identity, beliefs, preferences


class BondType(IntEnum):
    CAUSAL = 0         # "this led to that"
    SEMANTIC = 1       # "these are related concepts"
    TEMPORAL = 2       # "these happened together"
    CONTRADICTORY = 3  # "these conflict"


# Decay rates per memory type (fraction per day)
# Episodic fades fast unless reinforced. Identity persists.
DECAY_RATES = {
    MemoryType.EPISODIC: 0.07,    # 7% per day
    MemoryType.SEMANTIC: 0.02,    # 2% per day
    MemoryType.PROCEDURAL: 0.03,  # 3% per day
    MemoryType.SELF_MODEL: 0.01,  # 1% per day
}

# Thresholds
IMPORTANCE_CHAIN_THRESHOLD = 7    # Only commit memories with importance >= 7 on-chain
BOND_SIMILARITY_THRESHOLD = 0.3   # Minimum tag overlap for auto-bonding
DECAY_PRUNE_THRESHOLD = 0.15      # Prune memories below this strength
MAX_BONDS_PER_MEMORY = 10
MOLECULE_MIN_ATOMS = 3


# -----------------------------------------------------------------------
# Data Classes
# -----------------------------------------------------------------------
@dataclass
class CognitiveEntry:
    """A memory atom with cognitive metadata."""
    memory_id: int
    key: str
    content: str
    tags: List[str]
    source: str
    content_hash: str

    # Cognitive metadata
    memory_type: MemoryType
    importance: int          # 1-10 (Stanford Generative Agents scoring)
    emotional_weight: int    # 1-10
    strength: float          # 0.0-1.0 (current after decay)

    # Molecular
    molecule_id: int = 0     # 0 = unassigned
    bond_count: int = 0

    # Lifecycle
    promoted_from: Optional[MemoryType] = None
    access_count: int = 0
    created_at: float = 0.0
    last_decay_at: float = 0.0
    last_accessed_at: float = 0.0
    on_chain: bool = False   # Whether committed to chain


@dataclass
class MemoryBond:
    """A typed relationship between two memories."""
    from_id: int
    to_id: int
    bond_type: BondType
    strength: float   # 0.0-1.0
    created_at: float = 0.0


@dataclass
class Molecule:
    """A stable cluster of bonded memories."""
    id: int
    atom_ids: List[int]
    stability: float      # 0.0-1.0
    topic: str = ""
    bond_count: int = 0
    created_at: float = 0.0


@dataclass
class DreamResult:
    """Output of a dream cycle."""
    memories_decayed: int = 0
    memories_pruned: int = 0
    bonds_created: int = 0
    molecules_formed: int = 0
    promotions: int = 0
    timestamp: float = 0.0


# -----------------------------------------------------------------------
# Cognitive Memory Engine
# -----------------------------------------------------------------------
class CognitiveMemoryEngine:
    """
    The brain of FlowClaw's memory system.

    Manages cognitive memory types, molecular bonds, importance scoring,
    decay, dream cycles, and molecular retrieval.

    Sits between the relay API and the on-chain contracts:
    - Relay writes here first (speed)
    - Engine manages bonds, decay, retrieval in-memory
    - Significant memories get committed on-chain (permanence)
    """

    def __init__(self):
        self.entries: Dict[int, CognitiveEntry] = {}
        self.bonds: Dict[int, List[MemoryBond]] = defaultdict(list)    # from_id → bonds
        self.reverse_bonds: Dict[int, List[int]] = defaultdict(list)   # to_id → from_ids
        self.molecules: Dict[int, Molecule] = {}
        self.type_index: Dict[MemoryType, List[int]] = {t: [] for t in MemoryType}
        self.tag_index: Dict[str, Set[int]] = defaultdict(set)  # tag → memory_ids

        self._next_id = 1
        self._next_molecule_id = 1
        self.last_dream_at = 0.0
        self.dream_history: List[DreamResult] = []

    # -------------------------------------------------------------------
    # Store: Add a memory with cognitive classification
    # -------------------------------------------------------------------
    def store(
        self,
        key: str,
        content: str,
        tags: List[str],
        source: str,
        memory_type: MemoryType = MemoryType.EPISODIC,
        importance: int = 5,
        emotional_weight: int = 5,
    ) -> CognitiveEntry:
        """Store a new cognitive memory and auto-detect bonds."""

        now = time.time()
        content_hash = hashlib.sha256(content.encode()).hexdigest()

        # Check if key exists (update)
        existing = self._find_by_key(key)
        if existing:
            existing.content = content
            existing.content_hash = content_hash
            existing.tags = tags
            existing.strength = min(1.0, existing.strength + 0.1)  # Reinforce on update
            existing.access_count += 1
            existing.last_accessed_at = now
            # Update tag index
            self._rebuild_tag_index_for(existing.memory_id, tags)
            logging.info(f"[Cognitive] Updated memory '{key}' (reinforced to {existing.strength:.2f})")
            return existing

        # New memory
        memory_id = self._next_id
        self._next_id += 1

        entry = CognitiveEntry(
            memory_id=memory_id,
            key=key,
            content=content,
            tags=tags,
            source=source,
            content_hash=content_hash,
            memory_type=memory_type,
            importance=max(1, min(10, importance)),
            emotional_weight=max(1, min(10, emotional_weight)),
            strength=1.0,
            created_at=now,
            last_decay_at=now,
            last_accessed_at=now,
        )

        self.entries[memory_id] = entry
        self.type_index[memory_type].append(memory_id)
        for tag in tags:
            self.tag_index[tag.lower()].add(memory_id)

        # Auto-detect bonds to existing memories
        self._auto_bond(entry)

        logging.info(
            f"[Cognitive] Stored {MemoryType(memory_type).name} memory '{key}' "
            f"(importance={importance}, bonds={entry.bond_count})"
        )

        return entry

    # -------------------------------------------------------------------
    # Molecular Retrieval: O(k) instead of O(n)
    # -------------------------------------------------------------------
    def retrieve_molecular(
        self,
        query: str,
        max_results: int = 15,
        max_depth: int = 2,
    ) -> List[CognitiveEntry]:
        """
        Molecular retrieval: find seed memory, traverse bonds to get coherent cluster.

        Instead of scanning ALL memories (O(n)), we:
        1. Find the best seed memory matching the query
        2. Traverse bonds from the seed (O(k) where k = avg bonds ≈ 3-5)
        3. Return the molecule cluster — semantically coherent group

        This is the core insight from Mole-Syn.
        """

        if not self.entries:
            return []

        # Step 1: Find seed memories (top scoring against query)
        seeds = self._score_memories(query, top_k=3)
        if not seeds:
            return []

        # Step 2: Traverse bonds from each seed to build cluster
        visited: Set[int] = set()
        cluster: List[CognitiveEntry] = []

        for seed_id, seed_score in seeds:
            self._traverse_bonds(seed_id, max_depth, visited, cluster)

        # Step 3: Sort by combined relevance + importance + strength
        query_words = set(query.lower().split())
        scored = []
        for entry in cluster:
            relevance = self._compute_relevance(entry, query_words)
            composite = (
                relevance * 0.4 +
                (entry.importance / 10.0) * 0.25 +
                entry.strength * 0.2 +
                (entry.emotional_weight / 10.0) * 0.15
            )
            scored.append((composite, entry))

        scored.sort(key=lambda x: -x[0])

        # Apply decay-aware filtering: skip very weak memories
        results = [
            entry for score, entry in scored[:max_results]
            if entry.strength > 0.1
        ]

        return results

    def retrieve_by_type(self, memory_type: MemoryType) -> List[CognitiveEntry]:
        """Get all memories of a specific type, sorted by importance."""
        ids = self.type_index.get(memory_type, [])
        entries = [self.entries[mid] for mid in ids if mid in self.entries]
        entries.sort(key=lambda e: (-e.importance, -e.strength))
        return entries

    def retrieve_self_model(self) -> List[CognitiveEntry]:
        """Get the agent's self-model — identity, personality, preferences."""
        return self.retrieve_by_type(MemoryType.SELF_MODEL)

    def retrieve_procedures(self) -> List[CognitiveEntry]:
        """Get procedural memories — skills and workflows."""
        return self.retrieve_by_type(MemoryType.PROCEDURAL)

    # -------------------------------------------------------------------
    # Build Context for Chat (replaces old keyword matching)
    # -------------------------------------------------------------------
    def build_context(self, user_message: str) -> str:
        """
        Build memory context for the LLM system prompt.
        Uses molecular retrieval instead of flat keyword scan.
        Includes self-model and relevant procedural memories.
        """

        sections = []

        # 1. Self-model (always include — identity persists)
        self_model = self.retrieve_self_model()
        if self_model:
            lines = ["## Agent Identity & Preferences"]
            for entry in self_model[:5]:
                lines.append(f"- **{entry.key}**: {entry.content}")
            sections.append("\n".join(lines))

        # 2. Molecular retrieval for query-relevant memories
        relevant = self.retrieve_molecular(user_message, max_results=10)
        if relevant:
            lines = ["## Relevant Memories"]
            for entry in relevant:
                type_label = MemoryType(entry.memory_type).name.lower()
                strength_bar = "●" * int(entry.strength * 5) + "○" * (5 - int(entry.strength * 5))
                importance_str = f"importance:{entry.importance}"
                tags_str = f" (tags: {', '.join(entry.tags)})" if entry.tags else ""
                lines.append(
                    f"- [{type_label}|{strength_bar}|{importance_str}] "
                    f"**{entry.key}**: {entry.content}{tags_str}"
                )
            sections.append("\n".join(lines))

        # 3. Active procedures (if any match the query)
        procedures = self.retrieve_procedures()
        matching_procs = [
            p for p in procedures
            if self._compute_relevance(p, set(user_message.lower().split())) > 0.1
        ]
        if matching_procs:
            lines = ["## Relevant Procedures"]
            for proc in matching_procs[:3]:
                lines.append(f"- **{proc.key}**: {proc.content}")
            sections.append("\n".join(lines))

        if not sections:
            return ""

        context = "\n\n".join(sections)
        context += (
            "\n\nUse these memories to personalize responses. "
            "Memories with higher importance and strength are more reliable. "
            "Contradictory bonds indicate conflicting information — address these when relevant."
        )
        return context

    # -------------------------------------------------------------------
    # Dream Cycle: Consolidation, Decay, Promotion, Pruning
    # -------------------------------------------------------------------
    def run_dream_cycle(self) -> DreamResult:
        """
        The agent's 'sleep' phase. Consolidates memory:
        1. Decay: Apply time-based strength reduction per memory type
        2. Bond reinforcement: Strengthen bonds in molecules
        3. Promotion: Detect patterns in episodic → promote to semantic
        4. Molecule formation: Auto-cluster densely bonded memories
        5. Pruning: Remove weak isolated memories
        """

        now = time.time()
        result = DreamResult(timestamp=now)

        # --- Phase 1: Decay ---
        to_prune = []
        for mid, entry in self.entries.items():
            days_since = (now - entry.last_decay_at) / 86400.0
            if days_since < 0.01:  # Skip if decayed very recently
                continue

            decay_rate = DECAY_RATES.get(entry.memory_type, 0.05)
            decay_amount = decay_rate * days_since

            # Bond-based retention: each bond adds 10% decay resistance
            if entry.bond_count > 0:
                bond_bonus = min(1.0, entry.bond_count * 0.1)
                decay_amount *= (1.0 - bond_bonus)

            # High importance retention
            if entry.importance >= 8:
                decay_amount *= 0.5

            # High access count retention
            if entry.access_count >= 5:
                decay_amount *= 0.7

            new_strength = max(0.0, entry.strength - decay_amount)
            entry.strength = new_strength
            entry.last_decay_at = now
            result.memories_decayed += 1

            # Mark for pruning if weak AND isolated
            if new_strength < DECAY_PRUNE_THRESHOLD and entry.bond_count == 0:
                to_prune.append(mid)

        # --- Phase 2: Prune isolated weak memories ---
        for mid in to_prune:
            entry = self.entries.get(mid)
            if entry:
                # Don't prune self-model or high-importance
                if entry.memory_type == MemoryType.SELF_MODEL or entry.importance >= 7:
                    continue
                self._remove_entry(mid)
                result.memories_pruned += 1

        # --- Phase 3: Auto-bond detection for recent unbonded memories ---
        unbonded = [
            mid for mid, e in self.entries.items()
            if e.bond_count == 0 and e.strength > 0.3
        ]
        for mid in unbonded:
            entry = self.entries.get(mid)
            if entry:
                bonds_created = self._auto_bond(entry)
                result.bonds_created += bonds_created

        # --- Phase 4: Molecule formation ---
        for mid, entry in list(self.entries.items()):
            if entry.molecule_id == 0 and entry.bond_count >= 2:
                cluster = self._get_cluster(mid, max_depth=2)
                if len(cluster) >= MOLECULE_MIN_ATOMS:
                    mol = self._form_molecule(cluster)
                    if mol:
                        result.molecules_formed += 1

        # --- Phase 5: Promotion detection ---
        # Find episodic memories with same tags appearing 3+ times → promote to semantic
        promotions = self._detect_promotions()
        result.promotions = promotions

        self.last_dream_at = now
        self.dream_history.append(result)

        logging.info(
            f"[Dream Cycle] decayed={result.memories_decayed} "
            f"pruned={result.memories_pruned} bonds={result.bonds_created} "
            f"molecules={result.molecules_formed} promotions={result.promotions}"
        )

        return result

    # -------------------------------------------------------------------
    # Memory Classification (for auto-store from agent responses)
    # -------------------------------------------------------------------
    @staticmethod
    def classify_memory(key: str, content: str, tags: List[str]) -> Tuple[MemoryType, int, int]:
        """
        Auto-classify a memory's type, importance, and emotional weight.
        Uses heuristics — can be upgraded with LLM classification.
        """

        key_lower = key.lower()
        content_lower = content.lower()
        all_text = f"{key_lower} {content_lower} {' '.join(tags).lower()}"

        # Self-model detection
        self_keywords = {"preference", "identity", "personality", "believe", "value",
                         "priority", "style", "tone", "approach", "i am", "my role"}
        if any(kw in all_text for kw in self_keywords):
            return MemoryType.SELF_MODEL, 8, 7

        # Procedural detection
        proc_keywords = {"how to", "steps", "workflow", "process", "procedure",
                         "to do", "recipe", "method", "algorithm", "deploy", "build"}
        if any(kw in all_text for kw in proc_keywords):
            return MemoryType.PROCEDURAL, 6, 4

        # Semantic detection (facts, knowledge)
        sem_keywords = {"means", "is defined", "fact", "knowledge", "definition",
                        "concept", "theory", "principle", "always", "never"}
        if any(kw in all_text for kw in sem_keywords):
            return MemoryType.SEMANTIC, 6, 3

        # Default: episodic
        # Score importance based on content signals
        importance = 5
        emotional = 5

        # Importance boosters
        if any(w in content_lower for w in ["important", "critical", "key", "must", "essential"]):
            importance = min(10, importance + 2)
        if any(w in content_lower for w in ["decision", "choice", "trade", "agreement"]):
            importance = min(10, importance + 1)
            emotional = min(10, emotional + 1)
        if any(w in content_lower for w in ["error", "mistake", "failure", "bug"]):
            importance = min(10, importance + 1)
            emotional = min(10, emotional + 2)

        return MemoryType.EPISODIC, importance, emotional

    # -------------------------------------------------------------------
    # Get stats for dashboard
    # -------------------------------------------------------------------
    def get_stats(self) -> Dict:
        """Return cognitive memory statistics."""
        type_counts = {t.name.lower(): len(ids) for t, ids in self.type_index.items()}
        avg_strength = 0.0
        avg_importance = 0.0
        if self.entries:
            avg_strength = sum(e.strength for e in self.entries.values()) / len(self.entries)
            avg_importance = sum(e.importance for e in self.entries.values()) / len(self.entries)

        return {
            "totalMemories": len(self.entries),
            "totalBonds": sum(len(b) for b in self.bonds.values()),
            "totalMolecules": len(self.molecules),
            "typeCounts": type_counts,
            "avgStrength": round(avg_strength, 3),
            "avgImportance": round(avg_importance, 1),
            "lastDreamCycle": self.last_dream_at,
            "dreamCycleCount": len(self.dream_history),
        }

    # -------------------------------------------------------------------
    # Export for frontend / API
    # -------------------------------------------------------------------
    def export_entries(self) -> List[Dict]:
        """Export all entries for API consumption."""
        return [
            {
                "id": e.memory_id,
                "key": e.key,
                "content": e.content,
                "tags": e.tags,
                "source": e.source,
                "memoryType": e.memory_type,
                "memoryTypeName": MemoryType(e.memory_type).name.lower(),
                "importance": e.importance,
                "emotionalWeight": e.emotional_weight,
                "strength": round(e.strength, 3),
                "bondCount": e.bond_count,
                "moleculeId": e.molecule_id,
                "accessCount": e.access_count,
                "onChain": e.on_chain,
                "contentHash": e.content_hash,
            }
            for e in sorted(
                self.entries.values(),
                key=lambda x: (-x.importance, -x.strength)
            )
        ]

    def export_bonds(self) -> List[Dict]:
        """Export all bonds for API / visualization."""
        all_bonds = []
        for from_id, bond_list in self.bonds.items():
            for bond in bond_list:
                all_bonds.append({
                    "from": bond.from_id,
                    "to": bond.to_id,
                    "bondType": bond.bond_type,
                    "bondTypeName": BondType(bond.bond_type).name.lower(),
                    "strength": round(bond.strength, 3),
                })
        return all_bonds

    def export_molecules(self) -> List[Dict]:
        """Export molecules for API."""
        return [
            {
                "id": mol.id,
                "atomIds": mol.atom_ids,
                "stability": round(mol.stability, 3),
                "topic": mol.topic,
                "bondCount": mol.bond_count,
                "atomCount": len(mol.atom_ids),
            }
            for mol in self.molecules.values()
        ]

    # -------------------------------------------------------------------
    # Ingest existing flat memories (migration from old system)
    # -------------------------------------------------------------------
    def ingest_flat_memory(self, memory_id: int, key: str, content: str,
                           tags: List[str], source: str) -> CognitiveEntry:
        """Import a flat memory from the old system into the cognitive engine."""
        memory_type, importance, emotional = self.classify_memory(key, content, tags)
        entry = self.store(
            key=key,
            content=content,
            tags=tags,
            source=source,
            memory_type=memory_type,
            importance=importance,
            emotional_weight=emotional,
        )
        return entry

    # -------------------------------------------------------------------
    # Internal helpers
    # -------------------------------------------------------------------
    def _find_by_key(self, key: str) -> Optional[CognitiveEntry]:
        """Find entry by key."""
        for entry in self.entries.values():
            if entry.key == key:
                return entry
        return None

    def _score_memories(self, query: str, top_k: int = 3) -> List[Tuple[int, float]]:
        """Score all memories against a query. Returns [(memory_id, score)]."""
        query_words = set(query.lower().split())
        if not query_words:
            return []

        scored = []
        for mid, entry in self.entries.items():
            relevance = self._compute_relevance(entry, query_words)
            if relevance > 0:
                # Composite score: relevance + importance + strength + recency
                recency = max(0, 1.0 - (time.time() - entry.last_accessed_at) / (86400 * 7))
                composite = (
                    relevance * 0.5 +
                    (entry.importance / 10.0) * 0.2 +
                    entry.strength * 0.2 +
                    recency * 0.1
                )
                scored.append((mid, composite))

        scored.sort(key=lambda x: -x[1])
        return scored[:top_k]

    def _compute_relevance(self, entry: CognitiveEntry, query_words: Set[str]) -> float:
        """Compute keyword relevance score between entry and query words."""
        if not query_words:
            return 0.0

        entry_words = set()
        entry_words.update(entry.key.lower().replace("-", " ").replace("_", " ").split())
        entry_words.update(entry.content.lower().split())
        entry_words.update(t.lower() for t in entry.tags)

        overlap = len(query_words & entry_words)
        return overlap / len(query_words) if query_words else 0.0

    def _traverse_bonds(self, seed_id: int, max_depth: int,
                        visited: Set[int], result: List[CognitiveEntry]):
        """BFS traversal of memory bond graph from seed."""
        queue = [seed_id]
        depth = 0

        while queue and depth < max_depth:
            next_queue = []
            for mid in queue:
                if mid in visited:
                    continue
                visited.add(mid)
                if mid in self.entries:
                    result.append(self.entries[mid])
                    # Increment access count
                    self.entries[mid].access_count += 1
                    self.entries[mid].last_accessed_at = time.time()

                    # Forward bonds
                    for bond in self.bonds.get(mid, []):
                        if bond.to_id not in visited:
                            next_queue.append(bond.to_id)

                    # Reverse bonds
                    for from_id in self.reverse_bonds.get(mid, []):
                        if from_id not in visited:
                            next_queue.append(from_id)

            queue = next_queue
            depth += 1

    def _auto_bond(self, entry: CognitiveEntry) -> int:
        """Auto-detect and create bonds between new entry and existing memories."""
        bonds_created = 0

        if entry.bond_count >= MAX_BONDS_PER_MEMORY:
            return 0

        entry_tags = set(t.lower() for t in entry.tags)

        for mid, other in self.entries.items():
            if mid == entry.memory_id:
                continue
            if entry.bond_count >= MAX_BONDS_PER_MEMORY:
                break

            other_tags = set(t.lower() for t in other.tags)

            # Semantic bond: tag overlap
            if entry_tags and other_tags:
                overlap = len(entry_tags & other_tags)
                total = len(entry_tags | other_tags)
                similarity = overlap / total if total > 0 else 0

                if similarity >= BOND_SIMILARITY_THRESHOLD:
                    bond = MemoryBond(
                        from_id=entry.memory_id,
                        to_id=mid,
                        bond_type=BondType.SEMANTIC,
                        strength=min(1.0, similarity),
                        created_at=time.time(),
                    )
                    self.bonds[entry.memory_id].append(bond)
                    self.reverse_bonds[mid].append(entry.memory_id)
                    entry.bond_count += 1
                    other.bond_count += 1
                    bonds_created += 1

            # Temporal bond: created within 1 hour of each other
            if abs(entry.created_at - other.created_at) < 3600:
                # Check if temporal bond already exists
                has_temporal = any(
                    b.to_id == mid and b.bond_type == BondType.TEMPORAL
                    for b in self.bonds.get(entry.memory_id, [])
                )
                if not has_temporal and entry.bond_count < MAX_BONDS_PER_MEMORY:
                    bond = MemoryBond(
                        from_id=entry.memory_id,
                        to_id=mid,
                        bond_type=BondType.TEMPORAL,
                        strength=0.5,
                        created_at=time.time(),
                    )
                    self.bonds[entry.memory_id].append(bond)
                    self.reverse_bonds[mid].append(entry.memory_id)
                    entry.bond_count += 1
                    other.bond_count += 1
                    bonds_created += 1

        return bonds_created

    def _get_cluster(self, seed_id: int, max_depth: int = 2) -> List[int]:
        """Get memory IDs in a cluster around seed."""
        visited: Set[int] = set()
        result: List[int] = []
        queue = [seed_id]
        depth = 0

        while queue and depth < max_depth:
            next_queue = []
            for mid in queue:
                if mid in visited:
                    continue
                visited.add(mid)
                result.append(mid)

                for bond in self.bonds.get(mid, []):
                    if bond.to_id not in visited:
                        next_queue.append(bond.to_id)
                for from_id in self.reverse_bonds.get(mid, []):
                    if from_id not in visited:
                        next_queue.append(from_id)

            queue = next_queue
            depth += 1

        return result

    def _form_molecule(self, atom_ids: List[int]) -> Optional[Molecule]:
        """Form a molecule from a cluster of memory IDs."""
        # Count internal bonds
        id_set = set(atom_ids)
        internal_bonds = 0
        for mid in atom_ids:
            for bond in self.bonds.get(mid, []):
                if bond.to_id in id_set:
                    internal_bonds += 1

        max_possible = len(atom_ids) * MAX_BONDS_PER_MEMORY
        stability = min(1.0, internal_bonds / max_possible) if max_possible > 0 else 0.0

        mol_id = self._next_molecule_id
        self._next_molecule_id += 1

        molecule = Molecule(
            id=mol_id,
            atom_ids=atom_ids,
            stability=stability,
            bond_count=internal_bonds,
            created_at=time.time(),
        )

        self.molecules[mol_id] = molecule

        # Assign molecule to atoms
        for mid in atom_ids:
            if mid in self.entries:
                self.entries[mid].molecule_id = mol_id

        return molecule

    def _detect_promotions(self) -> int:
        """
        Detect patterns in episodic memories that should promote to semantic.
        If 3+ episodic memories share significant tag overlap, the pattern
        is a semantic fact.
        """
        promotions = 0
        episodic_ids = self.type_index.get(MemoryType.EPISODIC, [])

        # Group by tag combinations
        tag_groups: Dict[str, List[int]] = defaultdict(list)
        for mid in episodic_ids:
            entry = self.entries.get(mid)
            if entry and entry.tags:
                tag_key = "|".join(sorted(t.lower() for t in entry.tags))
                tag_groups[tag_key].append(mid)

        # Promote groups with 3+ members
        for tag_key, group_ids in tag_groups.items():
            if len(group_ids) >= 3:
                # Find highest-importance entry in group — promote it
                best_id = max(group_ids, key=lambda m: self.entries[m].importance)
                entry = self.entries.get(best_id)
                if entry and entry.memory_type == MemoryType.EPISODIC:
                    old_type = entry.memory_type
                    entry.memory_type = MemoryType.SEMANTIC
                    entry.promoted_from = old_type
                    entry.strength = 1.0  # Reset on promotion
                    entry.importance = min(10, entry.importance + 1)

                    # Update type index
                    if best_id in self.type_index[MemoryType.EPISODIC]:
                        self.type_index[MemoryType.EPISODIC].remove(best_id)
                    self.type_index[MemoryType.SEMANTIC].append(best_id)

                    promotions += 1
                    logging.info(
                        f"[Dream] Promoted memory '{entry.key}' from episodic → semantic "
                        f"(3+ episodes with tags: {tag_key})"
                    )

        return promotions

    def _remove_entry(self, memory_id: int):
        """Remove a memory and clean up all indices."""
        entry = self.entries.get(memory_id)
        if not entry:
            return

        # Remove from type index
        type_list = self.type_index.get(entry.memory_type, [])
        if memory_id in type_list:
            type_list.remove(memory_id)

        # Remove from tag index
        for tag in entry.tags:
            tag_lower = tag.lower()
            if tag_lower in self.tag_index:
                self.tag_index[tag_lower].discard(memory_id)

        # Remove bonds (forward)
        if memory_id in self.bonds:
            for bond in self.bonds[memory_id]:
                if bond.to_id in self.reverse_bonds:
                    if memory_id in self.reverse_bonds[bond.to_id]:
                        self.reverse_bonds[bond.to_id].remove(memory_id)
                if bond.to_id in self.entries:
                    self.entries[bond.to_id].bond_count = max(0, self.entries[bond.to_id].bond_count - 1)
            del self.bonds[memory_id]

        # Remove reverse bonds
        if memory_id in self.reverse_bonds:
            for from_id in self.reverse_bonds[memory_id]:
                if from_id in self.bonds:
                    self.bonds[from_id] = [
                        b for b in self.bonds[from_id] if b.to_id != memory_id
                    ]
                if from_id in self.entries:
                    self.entries[from_id].bond_count = max(0, self.entries[from_id].bond_count - 1)
            del self.reverse_bonds[memory_id]

        # Remove from molecule
        if entry.molecule_id and entry.molecule_id in self.molecules:
            mol = self.molecules[entry.molecule_id]
            if memory_id in mol.atom_ids:
                mol.atom_ids.remove(memory_id)
                if len(mol.atom_ids) < 2:
                    # Dissolve molecule
                    for atom_id in mol.atom_ids:
                        if atom_id in self.entries:
                            self.entries[atom_id].molecule_id = 0
                    del self.molecules[entry.molecule_id]

        del self.entries[memory_id]

    def _rebuild_tag_index_for(self, memory_id: int, new_tags: List[str]):
        """Rebuild tag index for a specific memory."""
        # Remove from all tag sets
        for tag_set in self.tag_index.values():
            tag_set.discard(memory_id)
        # Add to new tags
        for tag in new_tags:
            self.tag_index[tag.lower()].add(memory_id)
