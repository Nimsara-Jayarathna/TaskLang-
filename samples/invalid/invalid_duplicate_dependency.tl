TASK test {
    RUN "npm test"
}

TASK deploy {
    RUN "deploy.sh"
}

TASK build {
    RUN "npm run build"
    AFTER test
    BEFORE deploy
}
