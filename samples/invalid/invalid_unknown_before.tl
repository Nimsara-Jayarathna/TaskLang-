TASK setup {
    RUN "setup.sh"
    BEFORE deploy
}
