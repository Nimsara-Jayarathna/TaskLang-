%{
/*
 * TaskLang++ parser and semantic checker
 *
 * This file defines the grammar for TaskLang++ and stores parsed task
 * definitions in a fixed-size array. After parsing, semantic validation checks
 * duplicate task names, required RUN statements, references, schedules and
 * circular dependencies.
 */
#include <ctype.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TASKS 100
#define MAX_SEMANTIC_MESSAGES 256
#define MAX_SEMANTIC_MESSAGE_LEN 512
#define MAX_NAME_LEN 64
#define MAX_COMMAND_LEN 256
#define MAX_SCHEDULE_TYPE_LEN 32
#define MAX_FREQUENCY_LEN 16
#define MAX_TIME_LEN 16

typedef struct Task {
    char name[MAX_NAME_LEN];
    char command[MAX_COMMAND_LEN];
    char scheduleType[MAX_SCHEDULE_TYPE_LEN];
    char frequency[MAX_FREQUENCY_LEN];
    char time[MAX_TIME_LEN];
    char dependency[MAX_NAME_LEN];
    char beforeTask[MAX_NAME_LEN];
    char conditionTask[MAX_NAME_LEN];
    int hasRun;
    int hasSchedule;
    int hasDependency;
    int hasBefore;
    int hasCondition;
    int line;
} Task;

static Task tasks[MAX_TASKS];
static char semanticMessages[MAX_SEMANTIC_MESSAGES][MAX_SEMANTIC_MESSAGE_LEN];
static int taskCount = 0;
static int currentTask = -1;
static int semanticErrors = 0;
static int semanticMessageCount = 0;
static int syntaxErrors = 0;

int yylex(void);
void yyerror(const char *message);

extern int yylineno;
extern char *yytext;

/* Start recording a new TASK block into the in-memory task list. */
static void begin_task(const char *name);
/* Finish the current TASK block (stop writing fields into it). */
static void finish_task(void);
/* Store the RUN command for the current task and reject duplicates. */
static void set_run(const char *command);
/* Store schedule information (EVERY DAY/WEEK or AT) and reject duplicates. */
static void set_schedule(const char *scheduleType, const char *frequency,
                         const char *time);
/* Store an AFTER/DEPENDS ON relationship and reject conflicting duplicates. */
static void set_dependency(const char *dependency);
/* Store a BEFORE relationship and reject conflicting duplicates. */
static void set_before(const char *beforeTask);
/* Store an IF success(task) condition and reject duplicates. */
static void set_condition(const char *conditionTask);
/* Record a human-readable semantic error message for later printing. */
static void add_semantic_error(const char *format, ...);
/* Print all collected semantic errors in a user-friendly list. */
static void print_semantic_errors(void);
/* Safely copy text into fixed-size fields (warn + truncate if too long). */
static void copy_field(char *destination, size_t destinationSize,
                       const char *source, const char *fieldName);
/* Run all post-parse "meaning" checks (required fields, references, cycles). */
static int validate_semantics(void);
/* Check whether a time string is a valid HH:MM in 24-hour format. */
static int validate_time(const char *time);
/* Find a task index by name (returns -1 when not found). */
static int find_task(const char *name);
/* Decide if one task depends on another (used for ordering + cycle checks). */
static int task_depends_on(int taskIndex, int prerequisiteIndex);
/* Detect circular dependencies across all tasks (reports semantic errors). */
static int detect_cycles(void);
/* Depth-first search helper used by detect_cycles(). */
static int dfs_cycle(int index, int *state);
/* Print a simulated "execution plan" (order + metadata), without running code. */
void print_execution(void);
/* Print prerequisite tasks before the given task (dependency-first ordering). */
static void print_execution_ordered(int index, int *printed);
/* Print one task's details (name, command, schedule, dependencies, condition). */
static void print_execution_task(const Task *task);
%}

%error-verbose

%union {
    char *str;
}

%token TASK "TASK"
%token RUN "RUN"
%token EVERY "EVERY"
%token DAY "DAY"
%token WEEK "WEEK"
%token AT "AT"
%token AFTER "AFTER"
%token BEFORE "BEFORE"
%token DEPENDS "DEPENDS"
%token ON "ON"
%token IF "IF"
%token SUCCESS "success"
%token LBRACE "{"
%token RBRACE "}"
%token LPAREN "("
%token RPAREN ")"
%token <str> IDENTIFIER "identifier"
%token <str> STRING "string"
%token UNKNOWN "unknown token"

%destructor { free($$); } IDENTIFIER STRING

%%

program
    : task_list
    ;

task_list
    : task_definition
    | task_list task_definition
    ;

task_definition
    : TASK IDENTIFIER { begin_task($2); }
      LBRACE task_body RBRACE  { finish_task(); free($2); }
    ;

task_body
    : /* empty */
    | task_body task_statement
    ;

task_statement
    : RUN STRING
        {
            set_run($2);
            free($2);
        }
    | EVERY DAY AT STRING
        {
            set_schedule("EVERY", "DAY", $4);
            free($4);
        }
    | EVERY WEEK AT STRING
        {
            set_schedule("EVERY", "WEEK", $4);
            free($4);
        }
    | AT STRING
        {
            set_schedule("AT", "", $2);
            free($2);
        }
    | AFTER IDENTIFIER
        {
            set_dependency($2);
            free($2);
        }
    | BEFORE IDENTIFIER
        {
            set_before($2);
            free($2);
        }
    | DEPENDS ON IDENTIFIER
        {
            set_dependency($3);
            free($3);
        }
    | IF SUCCESS LPAREN IDENTIFIER RPAREN
        {
            set_condition($4);
            free($4);
        }
    ;

%%

int main(void)
{
    /* Parse the input first; if syntax fails, stop immediately. */
    int parseResult = yyparse();

    if (parseResult != 0 || syntaxErrors > 0) {
        return EXIT_FAILURE;
    }

    /* After a clean parse, run semantic validation (cross-task rules). */
    validate_semantics();

    if (semanticErrors > 0) {
        printf("Parsing completed successfully.\n");
        print_semantic_errors();
        printf("Semantic validation failed with %d error(s).\n",
               semanticErrors);
        return EXIT_FAILURE;
    }

    print_execution();
    return EXIT_SUCCESS;
}

void yyerror(const char *message)
{
    /* Report grammar/syntax problems with line context for debugging input. */
    syntaxErrors++;

    if (yytext != NULL && yytext[0] != '\0') {
        fprintf(stderr, "Syntax error at line %d: %s near '%s'\n",
                yylineno, message, yytext);
    } else {
        fprintf(stderr, "Syntax error at line %d: %s\n", yylineno, message);
    }
}

static void begin_task(const char *name)
{
    /* Create a new task entry and mark it as the "current task" being filled. */
    Task *task;

    if (taskCount >= MAX_TASKS) {
        add_semantic_error(
            "Semantic error at line %d: maximum number of tasks (%d) exceeded",
            yylineno, MAX_TASKS);
        currentTask = -1;
        return;
    }

    currentTask = taskCount;
    task = &tasks[taskCount];
    memset(task, 0, sizeof(*task));
    task->line = yylineno;
    copy_field(task->name, sizeof(task->name), name, "task name");
    taskCount++;
}

static void finish_task(void)
{
    /* Clear the current-task pointer so statements outside a task are ignored. */
    currentTask = -1;
}

static void set_run(const char *command)
{
    /* Save the RUN string for the current task (only allowed once). */
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasRun) {
        add_semantic_error(
            "Semantic error at line %d: duplicate RUN statement in task '%s'",
            yylineno, task->name);
        return;
    }

    task->hasRun = 1;
    copy_field(task->command, sizeof(task->command), command, "command");
}

static void set_schedule(const char *scheduleType, const char *frequency,
                         const char *time)
{
    /* Save schedule fields for the current task (only one schedule allowed). */
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasSchedule) {
        add_semantic_error(
            "Semantic error at line %d: duplicate schedule statement in task '%s'",
            yylineno, task->name);
        return;
    }

    task->hasSchedule = 1;
    copy_field(task->scheduleType, sizeof(task->scheduleType), scheduleType,
               "schedule type");
    copy_field(task->frequency, sizeof(task->frequency), frequency,
               "schedule frequency");
    copy_field(task->time, sizeof(task->time), time, "schedule time");
}

static void set_dependency(const char *dependency)
{
    /* Save a dependency for the current task and prevent multiple dependency rules. */
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasDependency) {
        add_semantic_error(
            "Semantic error at line %d: duplicate dependency statement in task '%s'",
            yylineno, task->name);
        return;
    }

    if (task->hasBefore) {
        add_semantic_error(
            "Semantic error at line %d: duplicate dependency statement in task '%s'",
            yylineno, task->name);
        return;
    }

    task->hasDependency = 1;
    copy_field(task->dependency, sizeof(task->dependency), dependency,
               "dependency");
}

static void set_before(const char *beforeTask)
{
    /* Save a BEFORE relationship for the current task and prevent conflicts. */
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasDependency || task->hasBefore) {
        add_semantic_error(
            "Semantic error at line %d: duplicate dependency statement in task '%s'",
            yylineno, task->name);
        return;
    }

    task->hasBefore = 1;
    copy_field(task->beforeTask, sizeof(task->beforeTask), beforeTask,
               "BEFORE task");
}

static void set_condition(const char *conditionTask)
{
    /* Save an IF success(task) condition for the current task (only once). */
    Task *task;

    if (currentTask < 0) {
        return;
    }

    task = &tasks[currentTask];

    if (task->hasCondition) {
        add_semantic_error(
            "Semantic error at line %d: duplicate condition statement in task '%s'",
            yylineno, task->name);
        return;
    }

    task->hasCondition = 1;
    copy_field(task->conditionTask, sizeof(task->conditionTask), conditionTask,
               "condition task");
}

static void add_semantic_error(const char *format, ...)
{
    /* Store an error message (up to a limit) and increment the error count. */
    va_list args;

    if (semanticMessageCount < MAX_SEMANTIC_MESSAGES) {
        va_start(args, format);
        vsnprintf(semanticMessages[semanticMessageCount],
                  sizeof(semanticMessages[semanticMessageCount]), format,
                  args);
        va_end(args);
        semanticMessageCount++;
    }

    semanticErrors++;
}

static void print_semantic_errors(void)
{
    /* Print all stored semantic error messages in the order they were found. */
    int i;

    for (i = 0; i < semanticMessageCount; i++) {
        printf("%s\n", semanticMessages[i]);
    }

    if (semanticErrors > semanticMessageCount) {
        printf("Semantic error: too many semantic errors to display completely\n");
    }
}

static void copy_field(char *destination, size_t destinationSize,
                       const char *source, const char *fieldName)
{
    /* Copy into a fixed-size buffer; warn when truncation might occur. */
    if (strlen(source) >= destinationSize) {
        add_semantic_error(
            "Semantic error at line %d: %s is too long and was truncated",
            yylineno, fieldName);
    }

    snprintf(destination, destinationSize, "%s", source);
}

static int validate_semantics(void)
{
    /* Enforce rules that require looking across tasks, not just local grammar. */
    int before = semanticErrors;
    int i;
    int j;

    for (i = 0; i < taskCount; i++) {
        for (j = i + 1; j < taskCount; j++) {
            if (strcmp(tasks[i].name, tasks[j].name) == 0) {
                add_semantic_error("Semantic error: duplicate task name '%s'",
                                   tasks[i].name);
            }
        }
    }

    for (i = 0; i < taskCount; i++) {
        if (!tasks[i].hasRun) {
            add_semantic_error(
                "Semantic error: task '%s' is missing required RUN statement",
                tasks[i].name);
        }

        if (tasks[i].hasSchedule && !validate_time(tasks[i].time)) {
            add_semantic_error(
                "Semantic error: task '%s' has invalid time '%s' (expected HH:MM)",
                tasks[i].name, tasks[i].time);
        }

        if (tasks[i].hasDependency && find_task(tasks[i].dependency) < 0) {
            add_semantic_error(
                "Semantic error: task '%s' depends on unknown task '%s'",
                tasks[i].name, tasks[i].dependency);
        }

        if (tasks[i].hasBefore && find_task(tasks[i].beforeTask) < 0) {
            add_semantic_error(
                "Semantic error: task '%s' must run before unknown task '%s'",
                tasks[i].name, tasks[i].beforeTask);
        }

        if (tasks[i].hasCondition && find_task(tasks[i].conditionTask) < 0) {
            add_semantic_error(
                "Semantic error: task '%s' has condition on unknown task '%s'",
                tasks[i].name, tasks[i].conditionTask);
        }
    }

    detect_cycles();

    return semanticErrors - before;
}

static int validate_time(const char *time)
{
    /* Accept only strict 24-hour times like 00:00 through 23:59. */
    int hour;
    int minute;

    if (strlen(time) != 5) {
        return 0;
    }

    if (!isdigit((unsigned char)time[0]) ||
        !isdigit((unsigned char)time[1]) ||
        time[2] != ':' ||
        !isdigit((unsigned char)time[3]) ||
        !isdigit((unsigned char)time[4])) {
        return 0;
    }

    hour = (time[0] - '0') * 10 + (time[1] - '0');
    minute = (time[3] - '0') * 10 + (time[4] - '0');

    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

static int find_task(const char *name)
{
    /* Linear lookup by task name (sufficient for the assignment-sized inputs). */
    int i;

    for (i = 0; i < taskCount; i++) {
        if (strcmp(tasks[i].name, name) == 0) {
            return i;
        }
    }

    return -1;
}

/*
 * Dependency direction used by validation and execution ordering:
 * - AFTER/DEPENDS ON: the current task depends on the named task.
 * - BEFORE: the named task depends on the current task.
 */
static int task_depends_on(int taskIndex, int prerequisiteIndex)
{
    /* Normalize AFTER/DEPENDS and BEFORE into one "depends on" direction. */
    if (tasks[taskIndex].hasDependency &&
        strcmp(tasks[taskIndex].dependency, tasks[prerequisiteIndex].name) == 0) {
        return 1;
    }

    if (tasks[prerequisiteIndex].hasBefore &&
        strcmp(tasks[prerequisiteIndex].beforeTask, tasks[taskIndex].name) == 0) {
        return 1;
    }

    return 0;
}

static int detect_cycles(void)
{
    /* Run DFS from each task to find dependency loops (A -> ... -> A). */
    int state[MAX_TASKS];
    int i;

    for (i = 0; i < taskCount; i++) {
        state[i] = 0;
    }

    for (i = 0; i < taskCount; i++) {
        if (state[i] == 0 && dfs_cycle(i, state)) {
            return 1;
        }
    }

    return 0;
}

/*
 * DFS state values:
 * 0 = not visited, 1 = currently visiting, 2 = fully checked.
 */
static int dfs_cycle(int index, int *state)
{
    /* DFS recursion: "visiting" nodes detect back-edges which indicate cycles. */
    int dependencyIndex;

    state[index] = 1;

    for (dependencyIndex = 0; dependencyIndex < taskCount; dependencyIndex++) {
        if (!task_depends_on(index, dependencyIndex)) {
            continue;
        }

        if (state[dependencyIndex] == 1) {
            add_semantic_error(
                "Semantic error: circular dependency detected involving task '%s'",
                tasks[dependencyIndex].name);
            return 1;
        }

        if (state[dependencyIndex] == 0 &&
            dfs_cycle(dependencyIndex, state)) {
            return 1;
        }
    }

    state[index] = 2;
    return 0;
}

/*
 * Print a simulated execution flow. This function does not execute scripts;
 * it only displays the order and metadata that would be used by a scheduler.
 */
void print_execution(void)
{
    /* Print a dependency-respecting plan; this is display-only (no execution). */
    int printed[MAX_TASKS];
    int i;

    for (i = 0; i < taskCount; i++) {
        printed[i] = 0;
    }

    printf("Parsing TaskLang++ input...\n\n");
    printf("--- EXECUTION START ---\n\n");

    for (i = 0; i < taskCount; i++) {
        print_execution_ordered(i, printed);
    }

    printf("--- EXECUTION COMPLETE ---\n");
}

/*
 * Bonus behavior: print dependency tasks first. Semantic validation has already
 * rejected unknown and circular dependencies before this function is called.
 */
static void print_execution_ordered(int index, int *printed)
{
    /* Ensure prerequisites are printed first by recursively printing dependencies. */
    int dependencyIndex;

    if (printed[index]) {
        return;
    }

    for (dependencyIndex = 0; dependencyIndex < taskCount; dependencyIndex++) {
        if (task_depends_on(index, dependencyIndex)) {
            print_execution_ordered(dependencyIndex, printed);
        }
    }

    print_execution_task(&tasks[index]);
    printed[index] = 1;
}

static void print_execution_task(const Task *task)
{
    /* Print one task's stored metadata in a readable format. */
    printf("Executing Task: %s\n", task->name);
    printf("  Script: \"%s\"\n", task->command);

    if (task->hasSchedule) {
        if (strcmp(task->scheduleType, "EVERY") == 0) {
            printf("  Schedule: EVERY %s AT %s\n",
                   task->frequency, task->time);
        } else {
            printf("  Schedule: AT %s\n", task->time);
        }
    } else {
        printf("  Schedule:\n");
    }

    if (task->hasDependency) {
        printf("  Depends on: %s\n", task->dependency);
    }

    if (task->hasBefore) {
        printf("  Before: %s\n", task->beforeTask);
    }

    if (task->hasCondition) {
        printf("  Condition: success\n");
    }

    printf("\n");
}
