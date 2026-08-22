#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <stdbool.h>
#include <ctype.h>
#include <limits.h>
#include <libgen.h>

#define MAX_PATH 1024
#define MAX_LINE 4096

// Global variables for counters
int NumRemoved = 0;
int NumAdded = 0;

// Helper to check if a file exists
bool file_exists(const char *path) {
    return access(path, F_OK) == 0;
}

// Helper to write string to file
void write_to_file(const char *path, const char *content) {
    FILE *f = fopen(path, "w");
    if (f) {
        fputs(content, f);
        fclose(f);
    }
}

// Simple JSON string extractor (very basic, assumes no escaped quotes inside string for simplicity or handles them minimally)
// Returns a newly allocated string that must be freed.
char *get_json_value(const char *json, const char *key) {
    char search_key[256];
    snprintf(search_key, sizeof(search_key), "\"%s\"", key);
    
    char *pos = strstr(json, search_key);
    if (!pos) return NULL;

    // Move past key
    pos += strlen(search_key);
    
    // Find colon
    pos = strchr(pos, ':');
    if (!pos) return NULL;
    pos++;

    // Skip whitespace
    while (*pos && isspace((unsigned char)*pos)) pos++;

    if (*pos == '"') {
        // String value
        pos++;
        char *end = pos;
        while (*end && *end != '"') {
            if (*end == '\\' && *(end+1)) end++; // Skip escaped char
            end++;
        }
        size_t len = end - pos;
        char *val = malloc(len + 1);
        strncpy(val, pos, len);
        val[len] = '\0';
        return val;
    } else {
        // null or other types (we mainly care about strings here, but extlist can be null)
        if (strncmp(pos, "null", 4) == 0) return NULL;
        // For now, we only implement string extraction as per requirement
        return NULL;
    }
}

// Check if file has one of the extensions
bool has_extension(const char *filename, const char *extlist) {
    if (!extlist || strlen(extlist) == 0) return true; // If no extlist, assume all files (except excluded ones)

    const char *dot = strrchr(filename, '.');
    if (!dot) return false;
    dot++; // Skip dot

    // extlist is "zip|7z|rar"
    char *list_copy = strdup(extlist);
    char *token = strtok(list_copy, "|");
    while (token) {
        if (strcasecmp(dot, token) == 0) {
            free(list_copy);
            return true;
        }
        token = strtok(NULL, "|");
    }
    free(list_copy);
    return false;
}

// Recursive search for ROMs
// depth: current depth (starts at 1)
// max_depth: 2
bool find_roms(const char *base_path, const char *extlist, int depth, int max_depth) {
    if (depth > max_depth) return false;

    DIR *dir = opendir(base_path);
    if (!dir) return false;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

        char path[MAX_PATH];
        snprintf(path, sizeof(path), "%s/%s", base_path, entry->d_name);

        struct stat statbuf;
        if (stat(path, &statbuf) != 0) continue;

        if (S_ISDIR(statbuf.st_mode)) {
            if (find_roms(path, extlist, depth + 1, max_depth)) {
                closedir(dir);
                return true;
            }
        } else if (S_ISREG(statbuf.st_mode)) {
            // Check exclusions
            if (strcmp(entry->d_name, ".gitkeep") == 0) continue;
            const char *ext = strrchr(entry->d_name, '.');
            if (ext) {
                if (strcmp(ext, ".db") == 0) continue;
                if (strcmp(ext, ".launch") == 0) continue;
            }

            // Check extensions
            if (extlist == NULL || has_extension(entry->d_name, extlist)) {
                closedir(dir);
                return true;
            }
        }
    }

    closedir(dir);
    return false;
}

int main(int argc, char *argv[]) {
    // 1. Setup Environment
    setenv("PATH", "/mnt/SDCARD/System/bin:/usr/bin:/bin", 1);
    
    // Set LD_LIBRARY_PATH for child processes (sdl2imgshow)
    const char *existing_ld = getenv("LD_LIBRARY_PATH");
    char new_ld[4096];
    if (existing_ld) {
        snprintf(new_ld, sizeof(new_ld), "/mnt/SDCARD/System/lib:/usr/trimui/lib:%s", existing_ld);
    } else {
        strcpy(new_ld, "/mnt/SDCARD/System/lib:/usr/trimui/lib");
    }
    setenv("LD_LIBRARY_PATH", new_ld, 1);
    
    // Configuring CPU
    write_to_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor", "performance\n");
    write_to_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq", "1416000\n");

    bool silent = false;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-s") == 0) {
            silent = true;
            break;
        }
    }

    const char *emu_folder = "/mnt/SDCARD/Emus";
    const char *json_file = "/mnt/SDCARD/Emus/show.json";

    // PICO-8 Logic
    if (file_exists("/mnt/SDCARD/Emus/PICO/PICO8_Wrapper/bin/pico8_64") && 
        file_exists("/mnt/SDCARD/Emus/PICO/PICO8_Wrapper/bin/pico8.dat")) {
        if (file_exists("/mnt/SDCARD/Roms/PICO/° Run Splore.launch")) {
            rename("/mnt/SDCARD/Roms/PICO/° Run Splore.launch", "/mnt/SDCARD/Roms/PICO/° Run Splore.p8");
            unlink("/mnt/SDCARD/Roms/PICO/PICO_cache7.db");
        }
    }

    // Buffer for JSON output
    // Assuming a reasonable max size or we could use dynamic string builder. 
    // Let's use a large buffer for simplicity and speed.
    char *json_output = malloc(1024 * 1024); // 1MB should be enough
    if (!json_output) return 1;
    strcpy(json_output, "[");

    DIR *dir = opendir(emu_folder);
    if (dir) {
        struct dirent *entry;
        bool first_entry = true;

        while ((entry = readdir(dir)) != NULL) {
            if (entry->d_type != DT_DIR) continue; // Only directories
            if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) continue;

            char subfolder_path[MAX_PATH];
            snprintf(subfolder_path, sizeof(subfolder_path), "%s/%s", emu_folder, entry->d_name);

            char config_path[MAX_PATH];
            snprintf(config_path, sizeof(config_path), "%s/config.json", subfolder_path);

            if (file_exists(config_path)) {
                // Read config.json
                FILE *f = fopen(config_path, "r");
                if (!f) continue;
                fseek(f, 0, SEEK_END);
                long fsize = ftell(f);
                fseek(f, 0, SEEK_SET);
                char *config_content = malloc(fsize + 1);
                fread(config_content, 1, fsize, f);
                config_content[fsize] = '\0';
                fclose(f);

                char *rompath = get_json_value(config_content, "rompath");
                char *label = get_json_value(config_content, "label");
                char *extlist = get_json_value(config_content, "extlist");

                free(config_content);

                if (!label) {
                    if (rompath) free(rompath);
                    if (extlist) free(extlist);
                    continue;
                }

                // Resolve RomPath
                char abs_rompath[MAX_PATH];
                if (rompath && rompath[0] == '/') {
                    strcpy(abs_rompath, rompath);
                } else if (rompath) {
                    // Relative path
                    char temp_path[MAX_PATH];
                    snprintf(temp_path, sizeof(temp_path), "%s/%s", subfolder_path, rompath);
                    if (!realpath(temp_path, abs_rompath)) {
                        strcpy(abs_rompath, temp_path); // Fallback
                    }
                } else {
                    // Default? Script implies rompath exists.
                    strcpy(abs_rompath, subfolder_path);
                }

                int show = 0;
                if (entry->d_name[0] == '_') {
                    printf("Removing %s emulator (!! Exception for \"%s\" !!).\n", label, entry->d_name);
                    show = 0;
                } else {
                    // Check for ROMs
                    if (find_roms(abs_rompath, extlist, 1, 2)) {
                        printf("Adding %s emulator (roms found in \"%s\" folder).\n", label, entry->d_name);
                        show = 1;
                        NumAdded++;
                    } else {
                        printf("Removing %s emulator (!! no roms in \"%s\" folder !!).\n", label, entry->d_name);
                        show = 0;
                        NumRemoved++;
                    }
                }

                // Append to JSON
                if (!first_entry) strcat(json_output, ",");
                char json_entry[512];
                snprintf(json_entry, sizeof(json_entry), "{\"label\": \"%s\", \"show\": %d}", label, show);
                strcat(json_output, json_entry);
                first_entry = false;

                // Cleanup cache if empty
                char cache_file[MAX_PATH];
                snprintf(cache_file, sizeof(cache_file), "%s/%s_cache7.db", abs_rompath, entry->d_name);
                struct stat st;
                if (stat(cache_file, &st) == 0 && st.st_size == 0) {
                    unlink(cache_file);
                }

                if (rompath) free(rompath);
                if (label) free(label);
                if (extlist) free(extlist);
            }
        }
        closedir(dir);
    }

    strcat(json_output, "]");
    write_to_file(json_file, json_output);
    free(json_output);

    sync();

    if (!silent) {
        // The complex jq command for state.json
        // jq '(.list[].tabstate[] | select(has("pagestart"))).pagestart = 0 | (.list[].tabstate[] | select(has("pageend"))).pageend = 7' /tmp/state.json >/tmp/state.tmp && mv /tmp/state.tmp /tmp/state.json
        system("jq '(.list[].tabstate[] | select(has(\"pagestart\"))).pagestart = 0 | (.list[].tabstate[] | select(has(\"pageend\"))).pageend = 7' /tmp/state.json >/tmp/state.tmp && mv /tmp/state.tmp /tmp/state.json");
    }

    sync();

    printf("\n=============================\n");
    printf("%d displayed emulator(s)\n%d hidden emulator(s)\n", NumAdded, NumRemoved);
    printf("=============================\n\n");
    
    // Machine readable output for the wrapper script
    printf("NUM_ADDED=%d\n", NumAdded);
    printf("NUM_REMOVED=%d\n", NumRemoved);

    return 0;
}
