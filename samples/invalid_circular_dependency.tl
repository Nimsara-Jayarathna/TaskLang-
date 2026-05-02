TASK A {
    RUN "a.sh"
    AFTER B
}

TASK B {
    RUN "b.sh"
    AFTER A
}
