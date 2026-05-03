TASK A {
    RUN "a.sh"
    BEFORE B
}

TASK B {
    RUN "b.sh"
    BEFORE A
}
