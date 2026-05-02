TASK deploy {
    RUN "deploy.sh"
    AFTER build
}
