// get_scheduled_tasks.cdc
// List all active scheduled tasks for an account.

import "AgentScheduler"

access(all) fun main(address: Address): [AgentScheduler.ScheduledTask] {
    let account = getAuthAccount<auth(Storage) &Account>(address)
    if let scheduler = account.storage.borrow<&AgentScheduler.Scheduler>(
        from: AgentScheduler.SchedulerStoragePath
    ) {
        return scheduler.getActiveTasks()
    }
    return []
}
