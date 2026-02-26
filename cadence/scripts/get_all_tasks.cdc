// get_all_tasks.cdc
// Retrieve all scheduled tasks for an account.
// Returns active tasks with their execution schedules and configurations.

import "AgentScheduler"

access(all) struct AllTasksResult {
    access(all) let totalTasks: UInt64
    access(all) let activeTasks: [AgentScheduler.ScheduledTask]
    access(all) let recentExecutions: [AgentScheduler.TaskExecutionResult]

    init(
        totalTasks: UInt64,
        activeTasks: [AgentScheduler.ScheduledTask],
        recentExecutions: [AgentScheduler.TaskExecutionResult]
    ) {
        self.totalTasks = totalTasks
        self.activeTasks = activeTasks
        self.recentExecutions = recentExecutions
    }
}

access(all) fun main(address: Address): AllTasksResult {
    let account = getAuthAccount<auth(Storage) &Account>(address)

    var activeTasks: [AgentScheduler.ScheduledTask] = []
    var recentExecutions: [AgentScheduler.TaskExecutionResult] = []

    if let scheduler = account.storage.borrow<&AgentScheduler.Scheduler>(
        from: AgentScheduler.SchedulerStoragePath
    ) {
        activeTasks = scheduler.getActiveTasks()
        recentExecutions = scheduler.getExecutionHistory(limit: 20)

        return AllTasksResult(
            totalTasks: AgentScheduler.totalTasks,
            activeTasks: activeTasks,
            recentExecutions: recentExecutions
        )
    }

    return AllTasksResult(totalTasks: 0, activeTasks: [], recentExecutions: [])
}
