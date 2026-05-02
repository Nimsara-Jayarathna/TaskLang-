# Comments that start with # are ignored.
TASK cleanup {
    // Comments that start with // are also ignored.
    RUN "cleanup-temp.sh"
    EVERY DAY AT "23:45"
}
