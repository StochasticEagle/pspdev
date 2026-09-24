#include <pspctrl.h>
#include <pspdebug.h>
#include <pspiofilemgr.h>
#include <pspkernel.h>
#include <psploadexec.h>
#include <pspsysmem.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

PSP_MODULE_INFO("PSPDEV Test Suite", 0, 1, 0);
PSP_MAIN_THREAD_ATTR(PSP_THREAD_ATTR_USER);

#define MAX_TESTS 256
#define MAX_PATH_LENGTH 512
#define MAX_LINE_LENGTH 1024
#define PAGE_SIZE 20

typedef struct TestEntry {
    char scope[32];
    char module[96];
    char title[160];
    char path[256];
    int selected;
} TestEntry;

typedef struct RunState {
    int count;
    int position;
    int inflight;
    int indices[MAX_TESTS];
} RunState;

static TestEntry tests[MAX_TESTS];
static int test_count = 0;
static char base_path[MAX_PATH_LENGTH];
static char launcher_path[MAX_PATH_LENGTH];
static char results_path[MAX_PATH_LENGTH];
static char state_path[MAX_PATH_LENGTH];
static char aggregate_path[MAX_PATH_LENGTH];
static char failures_path[MAX_PATH_LENGTH];
static char build_info_path[MAX_PATH_LENGTH];

static void copy_string(char *destination, size_t destination_size, const char *source) {
    if (destination_size == 0) {
        return;
    }
    if (source == NULL) {
        destination[0] = '\0';
        return;
    }
    snprintf(destination, destination_size, "%s", source);
}

static void make_path(char *destination, size_t destination_size, const char *left, const char *right) {
    snprintf(destination, destination_size, "%s/%s", left, right);
}

static const char *argument_value(int argc, char **argv, const char *name) {
    int index;
    size_t length = strlen(name);

    for (index = 1; index < argc; index++) {
        if (strncmp(argv[index], name, length) == 0 && argv[index][length] == '=' && argv[index][length + 1] != '\0') {
            return argv[index] + length + 1;
        }
        if (strcmp(argv[index], name) == 0 && index + 1 < argc) {
            return argv[index + 1];
        }
    }
    return NULL;
}

static void initialize_paths(const char *argv0) {
    char *slash;

    copy_string(launcher_path, sizeof(launcher_path), argv0);
    copy_string(base_path, sizeof(base_path), argv0);
    slash = strrchr(base_path, '/');
    if (slash != NULL) {
        *slash = '\0';
    } else {
        copy_string(base_path, sizeof(base_path), ".");
    }

    make_path(results_path, sizeof(results_path), base_path, "results");
    make_path(state_path, sizeof(state_path), results_path, "run.state");
    make_path(aggregate_path, sizeof(aggregate_path), results_path, "latest.log");
    make_path(failures_path, sizeof(failures_path), results_path, "failures.md");
    make_path(build_info_path, sizeof(build_info_path), base_path, "build-info.txt");
    sceIoMkdir(results_path, 0777);
}

static int load_manifest(void) {
    char manifest_path[MAX_PATH_LENGTH];
    char line[MAX_LINE_LENGTH];
    FILE *file;

    make_path(manifest_path, sizeof(manifest_path), base_path, "tests.manifest");
    file = fopen(manifest_path, "r");
    if (file == NULL) {
        return -1;
    }

    test_count = 0;
    while (test_count < MAX_TESTS && fgets(line, sizeof(line), file) != NULL) {
        char *scope;
        char *module;
        char *title;
        char *path;

        if (line[0] == '#' || line[0] == '\n' || line[0] == '\r') {
            continue;
        }

        scope = strtok(line, "\t\r\n");
        module = strtok(NULL, "\t\r\n");
        title = strtok(NULL, "\t\r\n");
        path = strtok(NULL, "\t\r\n");
        if (scope == NULL || module == NULL || title == NULL || path == NULL) {
            fclose(file);
            return -2;
        }

        copy_string(tests[test_count].scope, sizeof(tests[test_count].scope), scope);
        copy_string(tests[test_count].module, sizeof(tests[test_count].module), module);
        copy_string(tests[test_count].title, sizeof(tests[test_count].title), title);
        copy_string(tests[test_count].path, sizeof(tests[test_count].path), path);
        tests[test_count].selected = 1;
        test_count++;
    }

    fclose(file);
    return test_count;
}

static int selected_count(void) {
    int index;
    int count = 0;

    for (index = 0; index < test_count; index++) {
        if (tests[index].selected) {
            count++;
        }
    }
    return count;
}

static int save_state(const RunState *state) {
    FILE *file;
    int index;

    file = fopen(state_path, "w");
    if (file == NULL) {
        return -1;
    }

    fprintf(file, "PSPTEST_STATE 1 %d %d %d\n", state->count, state->position, state->inflight);
    for (index = 0; index < state->count; index++) {
        fprintf(file, "%d\n", state->indices[index]);
    }
    fclose(file);
    return 0;
}

static int load_state(RunState *state) {
    FILE *file;
    int version;
    int index;

    file = fopen(state_path, "r");
    if (file == NULL) {
        return 0;
    }

    if (fscanf(file, "PSPTEST_STATE %d %d %d %d", &version, &state->count, &state->position, &state->inflight) != 4 || version != 1 || state->count < 0 || state->count > MAX_TESTS || state->position < 0 || state->position > state->count) {
        fclose(file);
        return -1;
    }

    for (index = 0; index < state->count; index++) {
        if (fscanf(file, "%d", &state->indices[index]) != 1 || state->indices[index] < 0 || state->indices[index] >= test_count) {
            fclose(file);
            return -1;
        }
    }

    fclose(file);
    return 1;
}

static void append_build_info(FILE *file) {
    FILE *source;
    char line[MAX_LINE_LENGTH];

    source = fopen(build_info_path, "r");
    if (source == NULL) {
        fprintf(file, "build-info unavailable\n");
        return;
    }

    while (fgets(line, sizeof(line), source) != NULL) {
        fputs(line, file);
    }
    fclose(source);
}

static int begin_reports(void) {
    FILE *aggregate;
    FILE *failures;

    aggregate = fopen(aggregate_path, "w");
    if (aggregate == NULL) {
        return -1;
    }

    fprintf(aggregate, "PSPDEV_TEST_RUN\n");
    fprintf(aggregate, "firmware_devkit=0x%08X\n", (unsigned int)sceKernelDevkitVersion());
    append_build_info(aggregate);
    fclose(aggregate);

    failures = fopen(failures_path, "w");
    if (failures == NULL) {
        return -1;
    }

    fprintf(failures, "# PSPDEV Test Failure Report\n\n");
    fprintf(failures, "Firmware devkit version: 0x%08X\n\n", (unsigned int)sceKernelDevkitVersion());
    fprintf(failures, "## Build information\n\n---\n");
    append_build_info(failures);
    fprintf(failures, "---\n");
    fclose(failures);
    return 0;
}

static void result_file_path(char *destination, size_t destination_size, int test_index) {
    snprintf(destination, destination_size, "%s/%s-%s.log", results_path, tests[test_index].scope, tests[test_index].module);
}

static int result_has_failure(const char *path) {
    FILE *file;
    char line[MAX_LINE_LENGTH];

    file = fopen(path, "r");
    if (file == NULL) {
        return 1;
    }

    while (fgets(line, sizeof(line), file) != NULL) {
        if (strstr(line, "\tFAIL\t") != NULL || strstr(line, "\tINTERACTIVE_FAIL\t") != NULL || strncmp(line, "RETURN\tFAIL\t", 12) == 0) {
            fclose(file);
            return 1;
        }
    }

    fclose(file);
    return 0;
}

static void append_result(int test_index, const char *path) {
    FILE *source;
    FILE *aggregate;
    FILE *failures;
    char line[MAX_LINE_LENGTH];
    int failed = result_has_failure(path);

    source = fopen(path, "r");
    aggregate = fopen(aggregate_path, "a");
    if (aggregate != NULL) {
        fprintf(aggregate, "\nTEST\t%s/%s\t%s\n", tests[test_index].scope, tests[test_index].module, path);
        if (source != NULL) {
            while (fgets(line, sizeof(line), source) != NULL) {
                fputs(line, aggregate);
            }
            rewind(source);
        } else {
            fprintf(aggregate, "CASE\tFAIL\tinfrastructure\tassertions=0\tmessage=result file unavailable\n");
        }
        fclose(aggregate);
    }

    if (failed) {
        failures = fopen(failures_path, "a");
        if (failures != NULL) {
            fprintf(failures, "\n## %s / %s\n\n", tests[test_index].scope, tests[test_index].module);
            fprintf(failures, "Test EBOOT: %s\n\n---\n", tests[test_index].path);
            if (source != NULL) {
                while (fgets(line, sizeof(line), source) != NULL) {
                    fputs(line, failures);
                }
            } else {
                fprintf(failures, "Result file unavailable\n");
            }
            fprintf(failures, "---\n");
            fclose(failures);
        }
    }

    if (source != NULL) {
        fclose(source);
    }
}

static void write_infrastructure_failure(int test_index, const char *message, int code) {
    char path[MAX_PATH_LENGTH];
    FILE *file;

    result_file_path(path, sizeof(path), test_index);
    file = fopen(path, "w");
    if (file != NULL) {
        fprintf(file, "PSPTEST\t1\n");
        fprintf(file, "SUITE\t%s/%s\n", tests[test_index].scope, tests[test_index].module);
        fprintf(file, "CASE\tFAIL\tinfrastructure\tassertions=0\tmessage=%s code=%d\n", message, code);
        fprintf(file, "SUMMARY\tpass=0\tfail=1\tskip=0\ttotal=1\n");
        fclose(file);
    }
    append_result(test_index, path);
}

static int launch_test(int test_index) {
    char test_path[MAX_PATH_LENGTH];
    char output_path[MAX_PATH_LENGTH];
    char arguments[1536];
    SceKernelLoadExecParam parameters;
    int length;

    make_path(test_path, sizeof(test_path), base_path, tests[test_index].path);
    result_file_path(output_path, sizeof(output_path), test_index);
    remove(output_path);

    length = snprintf(arguments, sizeof(arguments), "%s --psptest-output=%s --psptest-return=%s", test_path, output_path, launcher_path);
    if (length < 0 || (size_t)length >= sizeof(arguments)) {
        return -1;
    }

    memset(&parameters, 0, sizeof(parameters));
    parameters.size = sizeof(parameters);
    parameters.args = (SceSize)(length + 1);
    parameters.argp = arguments;
    parameters.key = NULL;
    return sceKernelLoadExec(test_path, &parameters);
}

static int run_next(RunState *state) {
    while (state->position < state->count) {
        int test_index = state->indices[state->position];
        int status;

        state->inflight = 1;
        if (save_state(state) < 0) {
            return -1;
        }

        status = launch_test(test_index);
        write_infrastructure_failure(test_index, "sceKernelLoadExec returned without starting test", status);

        state->inflight = 0;
        state->position++;
        if (save_state(state) < 0) {
            return -1;
        }
    }

    remove(state_path);
    return 0;
}

static int start_run(void) {
    RunState state;
    int index;

    memset(&state, 0, sizeof(state));
    for (index = 0; index < test_count; index++) {
        if (tests[index].selected) {
            state.indices[state.count++] = index;
        }
    }

    if (state.count == 0) {
        return -1;
    }

    if (begin_reports() < 0 || save_state(&state) < 0) {
        return -1;
    }

    return run_next(&state);
}

static int resume_run(const char *returned_result) {
    RunState state;
    int loaded = load_state(&state);

    if (loaded <= 0) {
        return loaded;
    }

    if (state.position >= state.count) {
        remove(state_path);
        return 0;
    }

    if (state.inflight) {
        int test_index = state.indices[state.position];

        if (returned_result != NULL) {
            append_result(test_index, returned_result);
        } else {
            write_infrastructure_failure(test_index, "selected test did not return to PSPDEV Test Suite", -1);
        }

        state.inflight = 0;
        state.position++;
        if (save_state(&state) < 0) {
            return -1;
        }
    }

    return run_next(&state);
}

static void select_all(int selected) {
    int index;
    for (index = 0; index < test_count; index++) {
        tests[index].selected = selected;
    }
}

static void draw_menu(int cursor, const char *message) {
    int page_start = (cursor / PAGE_SIZE) * PAGE_SIZE;
    int page_end = page_start + PAGE_SIZE;
    int index;

    if (page_end > test_count) {
        page_end = test_count;
    }

    pspDebugScreenClear();
    pspDebugScreenPrintf("PSPDEV Test Suite\n");
    pspDebugScreenPrintf("Selected tests always run; there are no hardware gates.\n\n");
    pspDebugScreenPrintf("Cross: run selected  Square: toggle  Triangle: all  Circle: none\n");
    pspDebugScreenPrintf("Up/Down: move  Start: exit\n\n");

    for (index = page_start; index < page_end; index++) {
        pspDebugScreenPrintf("%c [%c] %-10s %s\n", index == cursor ? '>' : ' ', tests[index].selected ? 'x' : ' ', tests[index].scope, tests[index].title);
    }

    pspDebugScreenPrintf("\nSelected: %d / %d\n", selected_count(), test_count);
    if (message != NULL && message[0] != '\0') {
        pspDebugScreenPrintf("%s\n", message);
    }
}

static void run_menu(void) {
    SceCtrlData pad;
    unsigned int previous = 0;
    int cursor = 0;
    char message[256] = "";

    sceCtrlSetSamplingCycle(0);
    sceCtrlSetSamplingMode(PSP_CTRL_MODE_DIGITAL);

    while (1) {
        unsigned int pressed;

        draw_menu(cursor, message);
        sceCtrlReadBufferPositive(&pad, 1);
        pressed = pad.Buttons & ~previous;
        previous = pad.Buttons;

        if ((pressed & PSP_CTRL_UP) != 0u && cursor > 0) {
            cursor--;
            message[0] = '\0';
        } else if ((pressed & PSP_CTRL_DOWN) != 0u && cursor + 1 < test_count) {
            cursor++;
            message[0] = '\0';
        } else if ((pressed & PSP_CTRL_SQUARE) != 0u && test_count > 0) {
            tests[cursor].selected = !tests[cursor].selected;
            message[0] = '\0';
        } else if ((pressed & PSP_CTRL_TRIANGLE) != 0u) {
            select_all(1);
            copy_string(message, sizeof(message), "All tests selected.");
        } else if ((pressed & PSP_CTRL_CIRCLE) != 0u) {
            select_all(0);
            copy_string(message, sizeof(message), "Selection cleared.");
        } else if ((pressed & PSP_CTRL_CROSS) != 0u) {
            if (selected_count() == 0) {
                copy_string(message, sizeof(message), "No tests selected.");
            } else if (start_run() < 0) {
                copy_string(message, sizeof(message), "Unable to start test run.");
            }
        } else if ((pressed & PSP_CTRL_START) != 0u) {
            sceKernelExitGame();
        }

        sceKernelDelayThread(50000);
    }
}

int main(int argc, char **argv) {
    const char *returned_result;
    RunState state;
    int state_status;

    pspDebugScreenInit();
    initialize_paths(argv[0]);

    if (load_manifest() < 0) {
        pspDebugScreenPrintf("Unable to load tests.manifest.\n");
        sceKernelDelayThread(5000000);
        sceKernelExitGame();
        return 1;
    }

    returned_result = argument_value(argc, argv, "--psptest-result");
    state_status = load_state(&state);
    if (state_status != 0) {
        int status = resume_run(returned_result);
        if (status < 0) {
            pspDebugScreenPrintf("Unable to resume PSPTEST run.\n");
            sceKernelDelayThread(3000000);
        }
    }

    run_menu();
    return 0;
}
