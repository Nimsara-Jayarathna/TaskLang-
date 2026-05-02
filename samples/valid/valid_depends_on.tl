TASK lint {
    RUN "npm run lint"
}

TASK test {
    RUN "npm test"
    DEPENDS ON lint
    IF success(lint)
}
