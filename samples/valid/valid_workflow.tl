TASK test {
    RUN "npm test"
    EVERY DAY AT "09:00"
}

TASK build {
    RUN "npm run build"
    AFTER test
    IF success(test)
}

TASK deploy {
    RUN "deploy.sh"
    DEPENDS ON build
    IF success(build)
}
