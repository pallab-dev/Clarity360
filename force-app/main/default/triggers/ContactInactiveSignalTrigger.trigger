trigger ContactInactiveSignalTrigger on Contact (before insert, before update) {
    // Intentionally minimal for dependency/UI visibility testing.
    for (Contact con : Trigger.new) {
        if (String.isBlank(con.LastName)) {
            con.LastName = 'Placeholder';
        }
    }
}
