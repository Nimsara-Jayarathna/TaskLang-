TASK compile {
    EVERY DAY AT "08:15"
    RUN "make build"
}

TASK package {
    IF success(compile)
    DEPENDS ON compile
    RUN "make package"
}
