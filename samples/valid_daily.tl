TASK backup {
    RUN "backup.sh"
    EVERY DAY AT "02:00"
}
