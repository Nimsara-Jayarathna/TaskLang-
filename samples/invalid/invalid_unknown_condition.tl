TASK deploy {
    RUN "deploy.sh"
    IF success(build)
}
