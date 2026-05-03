TASK transform {
    RUN "transform-data.sh"
}

TASK extract {
    RUN "extract-data.sh"
    BEFORE transform
}
