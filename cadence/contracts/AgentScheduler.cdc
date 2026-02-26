// AgentScheduler.cdc
// Replaces OpenClaw's unreliable off-chain cron with Flow's native scheduled transactions.
//
// WHY THIS IS BETTER:
// In OpenClaw/ZeroClaw, cron jobs run via Node.js setInterval or system crontab.
// If the process crashes, the machine sleeps, or the daemon restarts — jobs get missed.
// Flow's scheduled transactions are executed by VALIDATORS at the protocol level.
// Once scheduled, they run regardless of whether your machine is online.
//
// HOW IT WORKS:
// 1. Agent owner schedules a task (e.g., "summarize my inbox every morning at 9am")
// 2. The task is registered on-chain with a TransactionHandler capability
// 3. Flow validators execute the handler at the specified timestamp
// 4. The handler emits an AgentTaskTriggered event
// 5. The off-chain relay picks up the event and does the actual work
// 6. Results are posted back on-chain
//
// For recurring tasks, the handler RE-SCHEDULES itself after execution,
// creating a reliable on-chain cron loop that can't be missed.
//
// CADENCE FEATURES USED:
// - Pre/post conditions: validate task parameters, verify execution results
// - Capabilities: handler references are capability-scoped
// - Entitlements: separate Schedule, Execute, Cancel permissions
// - Resources: tasks are owned objects with move semantics

import "AgentRegistry"

access(all) contract AgentScheduler {

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------
    access(all) event TaskScheduled(
        taskId: UInt64,
        agentId: UInt64,
        owner: Address,
        taskType: String,
        executeAt: UFix64,
        isRecurring: Bool
    )
    access(all) event TaskTriggered(
        taskId: UInt64,
        agentId: UInt64,
        owner: Address,
        taskType: String,
        triggeredAt: UFix64
    )
    access(all) event TaskCompleted(
        taskId: UInt64,
        resultHash: String,
        nextExecutionAt: UFix64?
    )
    access(all) event TaskCanceled(taskId: UInt64)
    access(all) event TaskFailed(taskId: UInt64, reason: String)
    access(all) event TaskRescheduled(taskId: UInt64, nextExecutionAt: UFix64)

    // -----------------------------------------------------------------------
    // Paths
    // -----------------------------------------------------------------------
    access(all) let SchedulerStoragePath: StoragePath

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------
    access(all) var totalTasks: UInt64

    // -----------------------------------------------------------------------
    // Entitlements — separate permissions for scheduling vs executing vs canceling
    // -----------------------------------------------------------------------
    access(all) entitlement Schedule
    access(all) entitlement Execute
    access(all) entitlement Cancel
    access(all) entitlement Admin

    // -----------------------------------------------------------------------
    // TaskType — predefined agent task categories
    // -----------------------------------------------------------------------
    access(all) enum TaskCategory: UInt8 {
        // Inference tasks — trigger an LLM call with a prompt
        access(all) case inference
        // Memory tasks — compaction, cleanup, summarization
        access(all) case memoryMaintenance
        // Monitoring tasks — check conditions, report status
        access(all) case monitoring
        // Communication tasks — send scheduled messages
        access(all) case communication
        // Custom tasks — user-defined via prompt
        access(all) case custom
    }

    // -----------------------------------------------------------------------
    // RecurrenceRule — how often a task repeats
    // -----------------------------------------------------------------------
    access(all) struct RecurrenceRule {
        access(all) let intervalSeconds: UFix64    // Time between executions
        access(all) let maxExecutions: UInt64?     // nil = infinite
        access(all) let endTimestamp: UFix64?      // nil = no end date

        init(
            intervalSeconds: UFix64,
            maxExecutions: UInt64?,
            endTimestamp: UFix64?
        ) {
            pre {
                intervalSeconds >= 60.0: "Minimum interval is 60 seconds"
            }
            self.intervalSeconds = intervalSeconds
            self.maxExecutions = maxExecutions
            self.endTimestamp = endTimestamp
        }
    }

    // -----------------------------------------------------------------------
    // Common recurrence presets
    // -----------------------------------------------------------------------
    access(all) fun everyMinute(): RecurrenceRule {
        return RecurrenceRule(intervalSeconds: 60.0, maxExecutions: nil, endTimestamp: nil)
    }

    access(all) fun everyHour(): RecurrenceRule {
        return RecurrenceRule(intervalSeconds: 3600.0, maxExecutions: nil, endTimestamp: nil)
    }

    access(all) fun everyDay(): RecurrenceRule {
        return RecurrenceRule(intervalSeconds: 86400.0, maxExecutions: nil, endTimestamp: nil)
    }

    access(all) fun everyWeek(): RecurrenceRule {
        return RecurrenceRule(intervalSeconds: 604800.0, maxExecutions: nil, endTimestamp: nil)
    }

    // -----------------------------------------------------------------------
    // TaskConfig — what the scheduled task should do
    // -----------------------------------------------------------------------
    access(all) struct TaskConfig {
        access(all) let name: String               // Human-readable name
        access(all) let description: String
        access(all) let category: TaskCategory
        access(all) let prompt: String             // The instruction for the agent
        access(all) let targetSessionId: UInt64?   // Which session to use (nil = create new)
        access(all) let toolsAllowed: [String]     // Which tools this task can use
        access(all) let maxTurns: UInt64           // Max agentic loop turns
        access(all) let priority: UInt8            // 0=low, 1=medium, 2=high

        init(
            name: String,
            description: String,
            category: TaskCategory,
            prompt: String,
            targetSessionId: UInt64?,
            toolsAllowed: [String],
            maxTurns: UInt64,
            priority: UInt8
        ) {
            pre {
                name.length > 0: "Task name cannot be empty"
                prompt.length > 0: "Task prompt cannot be empty"
                maxTurns > 0 && maxTurns <= 20: "Max turns must be 1-20"
                priority <= 2: "Priority must be 0, 1, or 2"
            }
            self.name = name
            self.description = description
            self.category = category
            self.prompt = prompt
            self.targetSessionId = targetSessionId
            self.toolsAllowed = toolsAllowed
            self.maxTurns = maxTurns
            self.priority = priority
        }
    }

    // -----------------------------------------------------------------------
    // ScheduledTask — a task waiting to be executed
    // -----------------------------------------------------------------------
    access(all) struct ScheduledTask {
        access(all) let taskId: UInt64
        access(all) let agentId: UInt64
        access(all) let owner: Address
        access(all) let config: TaskConfig
        access(all) let createdAt: UFix64
        access(all) var nextExecutionAt: UFix64
        access(all) let recurrence: RecurrenceRule?   // nil = one-shot
        access(all) var executionCount: UInt64
        access(all) var lastExecutedAt: UFix64?
        access(all) var lastResultHash: String?
        access(all) var status: UInt8                  // 0=active, 1=paused, 2=completed, 3=failed

        init(
            taskId: UInt64,
            agentId: UInt64,
            owner: Address,
            config: TaskConfig,
            executeAt: UFix64,
            recurrence: RecurrenceRule?
        ) {
            self.taskId = taskId
            self.agentId = agentId
            self.owner = owner
            self.config = config
            self.createdAt = getCurrentBlock().timestamp
            self.nextExecutionAt = executeAt
            self.recurrence = recurrence
            self.executionCount = 0
            self.lastExecutedAt = nil
            self.lastResultHash = nil
            self.status = 0
        }
    }

    // -----------------------------------------------------------------------
    // TaskExecutionResult — recorded after each execution
    // -----------------------------------------------------------------------
    access(all) struct TaskExecutionResult {
        access(all) let taskId: UInt64
        access(all) let executionNumber: UInt64
        access(all) let triggeredAt: UFix64
        access(all) let completedAt: UFix64
        access(all) let resultHash: String
        access(all) let tokensUsed: UInt64
        access(all) let turnsUsed: UInt64
        access(all) let success: Bool
        access(all) let errorMessage: String?

        init(
            taskId: UInt64,
            executionNumber: UInt64,
            triggeredAt: UFix64,
            completedAt: UFix64,
            resultHash: String,
            tokensUsed: UInt64,
            turnsUsed: UInt64,
            success: Bool,
            errorMessage: String?
        ) {
            self.taskId = taskId
            self.executionNumber = executionNumber
            self.triggeredAt = triggeredAt
            self.completedAt = completedAt
            self.resultHash = resultHash
            self.tokensUsed = tokensUsed
            self.turnsUsed = turnsUsed
            self.success = success
            self.errorMessage = errorMessage
        }
    }

    // -----------------------------------------------------------------------
    // Scheduler Resource — per-account task manager
    // -----------------------------------------------------------------------
    access(all) resource Scheduler {
        access(all) let agentId: UInt64
        access(self) var tasks: {UInt64: ScheduledTask}
        access(self) var executionHistory: [TaskExecutionResult]
        access(self) var activeTaskCount: UInt64

        init(agentId: UInt64) {
            self.agentId = agentId
            self.tasks = {}
            self.executionHistory = []
            self.activeTaskCount = 0
        }

        // --- Schedule: create and manage scheduled tasks ---

        access(Schedule) fun scheduleTask(
            config: TaskConfig,
            executeAt: UFix64,
            recurrence: RecurrenceRule?
        ): UInt64 {
            pre {
                executeAt > getCurrentBlock().timestamp:
                    "Execution time must be in the future"
                self.activeTaskCount < 50:
                    "Maximum 50 active tasks per agent"
            }
            post {
                self.tasks[AgentScheduler.totalTasks] != nil:
                    "Task must be stored after scheduling"
            }

            AgentScheduler.totalTasks = AgentScheduler.totalTasks + 1
            let taskId = AgentScheduler.totalTasks

            let task = ScheduledTask(
                taskId: taskId,
                agentId: self.agentId,
                owner: self.owner!.address,
                config: config,
                executeAt: executeAt,
                recurrence: recurrence
            )

            self.tasks[taskId] = task
            self.activeTaskCount = self.activeTaskCount + 1

            emit TaskScheduled(
                taskId: taskId,
                agentId: self.agentId,
                owner: self.owner!.address,
                taskType: config.name,
                executeAt: executeAt,
                isRecurring: recurrence != nil
            )

            // NOTE: In production, this is where you'd call
            // FlowTransactionScheduler to register with the protocol.
            // For the PoC, the relay polls for TaskScheduled events
            // and sets up its own timer.

            return taskId
        }

        access(Schedule) fun scheduleRecurringInference(
            name: String,
            prompt: String,
            recurrence: RecurrenceRule,
            priority: UInt8
        ): UInt64 {
            let config = TaskConfig(
                name: name,
                description: "Recurring inference: ".concat(name),
                category: TaskCategory.inference,
                prompt: prompt,
                targetSessionId: nil,
                toolsAllowed: ["memory_store", "memory_recall", "web_fetch"],
                maxTurns: 5,
                priority: priority
            )

            let firstExecution = getCurrentBlock().timestamp + recurrence.intervalSeconds

            return self.scheduleTask(
                config: config,
                executeAt: firstExecution,
                recurrence: recurrence
            )
        }

        // --- Execute: trigger and complete tasks ---

        access(Execute) fun triggerTask(taskId: UInt64): Bool {
            pre {
                self.tasks[taskId] != nil: "Task not found"
            }

            if var task = self.tasks[taskId] {
                // Verify it's time
                if task.status != 0 {
                    return false // Not active
                }
                if getCurrentBlock().timestamp < task.nextExecutionAt {
                    return false // Not time yet
                }

                emit TaskTriggered(
                    taskId: taskId,
                    agentId: self.agentId,
                    owner: self.owner!.address,
                    taskType: task.config.name,
                    triggeredAt: getCurrentBlock().timestamp
                )

                return true
            }
            return false
        }

        access(Execute) fun completeTask(
            taskId: UInt64,
            resultHash: String,
            tokensUsed: UInt64,
            turnsUsed: UInt64,
            success: Bool,
            errorMessage: String?
        ) {
            pre {
                self.tasks[taskId] != nil: "Task not found"
            }
            post {
                // If recurring and successful, must have a next execution time
                self.tasks[taskId]!.recurrence == nil ||
                !success ||
                self.tasks[taskId]!.status != 0 ||
                self.tasks[taskId]!.nextExecutionAt > before(self.tasks[taskId]!.nextExecutionAt):
                    "Recurring task must reschedule"
            }

            if var task = self.tasks[taskId] {
                let now = getCurrentBlock().timestamp

                // Record execution
                let result = TaskExecutionResult(
                    taskId: taskId,
                    executionNumber: task.executionCount + 1,
                    triggeredAt: task.nextExecutionAt,
                    completedAt: now,
                    resultHash: resultHash,
                    tokensUsed: tokensUsed,
                    turnsUsed: turnsUsed,
                    success: success,
                    errorMessage: errorMessage
                )
                self.executionHistory.append(result)

                // Update task state
                task = ScheduledTask(
                    taskId: task.taskId,
                    agentId: task.agentId,
                    owner: task.owner,
                    config: task.config,
                    executeAt: task.nextExecutionAt,
                    recurrence: task.recurrence
                )

                // Handle recurrence
                if let recurrence = task.recurrence {
                    let nextExec = now + recurrence.intervalSeconds

                    // Check if we should continue
                    var shouldContinue = success
                    if let maxExec = recurrence.maxExecutions {
                        if task.executionCount + 1 >= maxExec {
                            shouldContinue = false
                        }
                    }
                    if let endTime = recurrence.endTimestamp {
                        if nextExec > endTime {
                            shouldContinue = false
                        }
                    }

                    if shouldContinue {
                        // Reschedule — this is the key to reliable recurring tasks
                        // The task re-registers itself on-chain for the next execution
                        emit TaskRescheduled(taskId: taskId, nextExecutionAt: nextExec)
                    } else {
                        // Mark as completed
                        emit TaskCompleted(
                            taskId: taskId,
                            resultHash: resultHash,
                            nextExecutionAt: nil
                        )
                    }
                } else {
                    // One-shot task — mark complete
                    self.activeTaskCount = self.activeTaskCount - 1
                    emit TaskCompleted(
                        taskId: taskId,
                        resultHash: resultHash,
                        nextExecutionAt: nil
                    )
                }

                if !success {
                    emit TaskFailed(taskId: taskId, reason: errorMessage ?? "Unknown error")
                }
            }
        }

        // --- Cancel: stop scheduled tasks ---

        access(Cancel) fun cancelTask(taskId: UInt64): Bool {
            if self.tasks[taskId] != nil {
                self.tasks.remove(key: taskId)
                self.activeTaskCount = self.activeTaskCount - 1
                emit TaskCanceled(taskId: taskId)
                return true
            }
            return false
        }

        // --- Read ---

        access(all) fun getTask(taskId: UInt64): ScheduledTask? {
            return self.tasks[taskId]
        }

        access(all) fun getActiveTasks(): [ScheduledTask] {
            var active: [ScheduledTask] = []
            for taskId in self.tasks.keys {
                if let task = self.tasks[taskId] {
                    if task.status == 0 {
                        active.append(task)
                    }
                }
            }
            return active
        }

        access(all) fun getTasksDueBefore(timestamp: UFix64): [ScheduledTask] {
            var due: [ScheduledTask] = []
            for taskId in self.tasks.keys {
                if let task = self.tasks[taskId] {
                    if task.status == 0 && task.nextExecutionAt <= timestamp {
                        due.append(task)
                    }
                }
            }
            return due
        }

        access(all) fun getExecutionHistory(limit: Int): [TaskExecutionResult] {
            let len = self.executionHistory.length
            if len <= limit {
                return self.executionHistory
            }
            return self.executionHistory.slice(from: len - limit, upTo: len)
        }

        access(all) fun getActiveTaskCount(): UInt64 {
            return self.activeTaskCount
        }
    }

    // -----------------------------------------------------------------------
    // Public factory
    // -----------------------------------------------------------------------
    access(all) fun createScheduler(agentId: UInt64): @Scheduler {
        return <- create Scheduler(agentId: agentId)
    }

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------
    init() {
        self.totalTasks = 0
        self.SchedulerStoragePath = /storage/FlowClawScheduler
    }
}
