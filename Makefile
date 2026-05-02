CC = gcc
CFLAGS = -Wall -Wextra -Wno-sign-compare
# lexer.l uses %option noyywrap, so libfl is not required by default.
# If your Flex installation requires it, build with: make LDLIBS=-lfl
LDLIBS ?=
TARGET = tasklang

.PHONY: all clean

all: $(TARGET)

$(TARGET): parser.tab.c lex.yy.c
	$(CC) $(CFLAGS) -o $(TARGET) parser.tab.c lex.yy.c $(LDLIBS)

parser.tab.c parser.tab.h: parser.y
	bison -d parser.y

lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

clean:
	rm -f $(TARGET) parser.tab.c parser.tab.h lex.yy.c
