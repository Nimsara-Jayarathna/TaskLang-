TASK test {
    RUN "npm test"
}

TASK build {
    RUN "npm run build"
    IF success(test)
    IF success(test)
}
