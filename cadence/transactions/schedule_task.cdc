// schedule_task.cdc
// Schedule a one-shot or recurring agent task.
// Replaces OpenClaw's cron with Flow's validator-executed scheduling.
//
// Examples:
//   "Summarize my inbox every morning" → recurring inference, interval=86400
//   "Check ETH price every hour" → recurring monitoring, interval=3600
//   "Send weekly report on Friday" → recurring communication, interval=604800
//   "Remind me in 30 minutes" → one-shot inference, no recurrence

import "AgentScheduler"

transaction(
    taskName: String,
    taskDescription: String,
    category: UInt8,
    prompt: String,
    maxTurns: UInt64,
    priority: UInt8,
    executeAtTimestamp: UFix64,
    isRecurring: Bool,
    intervalSeconds: UFix64?,
    maxExecutions: UInt64?
) {
    prepare(signer: auth(Storage) &Account) {
        let scheduler = signer.storage.borrow<auth(AgentScheduler.Schedule) &AgentScheduler.Scheduler>(
            from: AgentScheduler.SchedulerStoragePath
        ) ?? panic("Scheduler not found. Run initialize_account first.")

        // Build task config
        let taskCategory = AgentScheduler.TaskCategory(rawValue: category)
            ?? panic("Invalid task category")

        let config = AgentScheduler.TaskConfig(
            name: taskName,
            description: taskDescription,
            category: taskCategory,
            prompt: prompt,
            targetSessionId: nil,
            toolsAllowed: ["memory_store", "memory_recall", "web_fetch", "flow_query"],
            maxTurns: maxTurns,
            priority: priority
        )

        // Build recurrence rule if recurring
        var recurrence: AgentScheduler.RecurrenceRule? = nil
        if isRecurring {
            if let interval = intervalSeconds {
                recurrence = AgentScheduler.RecurrenceRule(
                    intervalSeconds: interval,
                    maxExecutions: maxExecutions,
                    endTimestamp: nil
                )
            }
        }

        let taskId = scheduler.scheduleTask(
            config: config,
            executeAt: executeAtTimestamp,
            recurrence: recurrence
        )

        log("Task scheduled with ID: ".concat(taskId.toString()))
    }
}
