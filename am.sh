#!/bin/bash

# Alias Manager (am) - A comprehensive tool for managing shell aliases and functions
# Compatible with macOS, Linux, and WSL
# Usage: am <command> [options] [arguments]

# Configuration
AM_HOME="${AM_HOME:-$XDG_CONFIG_HOME/alias-manager}"
ALIASES_FILE="${ALIASES_FILE:-$AM_HOME/aliases}"
FUNCTIONS_FILE="${FUNCTIONS_FILE:-$AM_HOME/functions}"
EDITOR="${EDITOR:-vi}"

# Detect OS for compatibility
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]] || [[ -n "$WSL_DISTRO_NAME" ]]; then
    OS_TYPE="linux"
fi

# Color codes for output (check if terminal supports colors)
# Always enable colors if FORCE_COLOR is set, otherwise check if stdout is a TTY
if [[ -n "$FORCE_COLOR" ]] || ([[ -t 1 ]] && [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]); then
    # Use printf to generate escape sequences for maximum compatibility
    RED=$(printf '\033[0;31m')
    GREEN=$(printf '\033[0;32m')
    YELLOW=$(printf '\033[1;33m')
    BLUE=$(printf '\033[0;34m')
    PURPLE=$(printf '\033[0;35m')
    CYAN=$(printf '\033[0;36m')
    NC=$(printf '\033[0m') # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
fi

# Global variables for audit (without -g for compatibility)
am_errors=0
am_warnings=0
am_info=0

# Global array to track temporary files for cleanup
declare -a am_temp_files=()

# Main function
function am() {
    local command="$1"
    shift
    
    case "$command" in
        add)
            am_add "$@"
            ;;
        list|ls)
            am_list "$@"
            ;;
        rm|remove)
            am_remove "$@"
            ;;
        audit)
            am_audit "$@"
            ;;
        path|show)
            am_path "$@"
            ;;
        install)
            am_install "$@"
            ;;
        status)
            am_status "$@"
            ;;
        search)
            am_search "$@"
            ;;
        edit)
            am_edit "$@"
            ;;
        update)
            am_update "$@"
            ;;
        help|--help|-h|"")
            am_help
            ;;
        *)
            echo "Unknown command: $command"
            echo "Use 'am help' for usage information"
            return 1
            ;;
    esac
}

# Help function
function am_help() {
    cat << EOF
${CYAN}Alias Manager (am)${NC} - Manage shell aliases and functions

${YELLOW}Usage:${NC}
  am <command> [options] [arguments]

${YELLOW}Commands:${NC}
  add          Add a new alias or function
  list, ls     List aliases and functions
  rm, remove   Remove an alias or function
  audit        Audit aliases and functions for issues
  path, show   Show file paths (use -o/--open to open)
  install      Setup auto-sourcing in shell config files
  status       Check installation and sourcing status
  search       Search aliases and functions by name or command
  edit         Edit an existing alias or function
  update       Update an existing alias or function
  help         Show this help message

${YELLOW}Arguments:${NC}
  {name}       The name parameter can refer to either an alias or function

${YELLOW}Examples:${NC}
  am add myname 'ls -la'         # Prompts for type (alias/function)
  am add -a ll 'ls -la'          # Add as alias
  am add -f greet 'echo Hi'      # Add as function
  am list                        # List all aliases and functions
  am list ll                     # Show definition of 'll' (alias or function)
  am rm ll                       # Remove 'll' (prompts if duplicate)
  am audit                       # Check for issues

Use 'am <command> --help' for more information on a specific command.
EOF
}

# Add command
function am_add() {
    local name=""
    local command=""
    local type=""
    local force=false
    local dry_run=false
    
    # Parse arguments with stricter validation
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--alias)
                if [[ -n "$type" ]]; then
                    echo -e "${RED}Error:${NC} Type already specified (${type})"
                    echo "Use 'am add --help' for usage information"
                    return 1
                fi
                type="alias"
                shift
                ;;
            -f|--function)
                if [[ -n "$type" ]]; then
                    echo -e "${RED}Error:${NC} Type already specified (${type})"
                    echo "Use 'am add --help' for usage information"
                    return 1
                fi
                type="function"
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                am_add_help
                return 0
                ;;
            *)
                # Handle positional arguments
                if [[ -z "$name" ]]; then
                    # First non-option argument is the name
                    name="$1"
                elif [[ "$1" == "function" && -z "$type" ]]; then
                    # Special case: "function" keyword when type not specified
                    type="function"
                else
                    # All remaining arguments are part of the command
                    if [[ -z "$command" ]]; then
                        command="$1"
                    else
                        command="$command $1"
                    fi
                fi
                shift
                ;;
        esac
    done
    
    # Validate name
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error:${NC} Name is required"
        echo "Use 'am add --help' for usage information"
        return 1
    fi
    
    # Validate name format (alphanumeric and underscore only)
    if ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        echo -e "${RED}Error:${NC} Invalid name '$name'"
        echo "Names must start with a letter or underscore and contain only letters, numbers, and underscores"
        return 1
    fi
    
    # Check for existing definitions
    local exists_in_aliases=$(check_alias_exists "$name")
    local exists_in_functions=$(check_function_exists "$name")
    
    # If --force is used, remove existing duplicates before adding
    if [[ "$force" == true ]]; then
        if [[ "$exists_in_aliases" == "true" ]]; then
            if [[ "$dry_run" == true ]]; then
                echo -e "${CYAN}[DRY RUN]${NC} Would remove existing alias '$name'"
            else
                # Remove existing alias silently (we're replacing it)
                am_remove --force -a "$name" >/dev/null 2>&1
            fi
        fi
        if [[ "$exists_in_functions" == "true" ]]; then
            if [[ "$dry_run" == true ]]; then
                echo -e "${CYAN}[DRY RUN]${NC} Would remove existing function '$name'"
            else
                # Remove existing function silently (we're replacing it)
                am_remove --force -f "$name" >/dev/null 2>&1
            fi
        fi
    elif [[ "$exists_in_aliases" == "true" || "$exists_in_functions" == "true" ]]; then
        echo -e "${YELLOW}Warning:${NC} Name '$name' already exists:"
        if [[ "$exists_in_aliases" == "true" ]]; then
            echo -e "  ${BLUE}Alias:${NC} $(get_alias_definition "$name")"
        fi
        if [[ "$exists_in_functions" == "true" ]]; then
            echo -e "  ${PURPLE}Function:${NC} $(get_function_summary "$name")"
        fi
        echo ""
        read_with_prompt "Do you want to continue? (y/N) " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 1
        fi
    fi
    
    # Determine type if not specified
    if [[ -z "$type" ]]; then
        echo "Select type for '$name':"
        echo "1) Alias"
        echo "2) Function"
        read_with_prompt "Choice (1-2): " -n 1 response
        echo
        case $response in
            1) type="alias" ;;
            2) type="function" ;;
            *) echo "Invalid choice. Aborted."; return 1 ;;
        esac
    fi
    
    # Add based on type
    if [[ "$dry_run" == true ]]; then
        echo -e "${CYAN}[DRY RUN]${NC} Would add ${type:-alias/function} '$name'"
        if [[ -n "$command" ]]; then
            echo "  Command: $command"
        else
            echo "  Command: (would prompt for input)"
        fi
        return 0
    fi
    
    if [[ "$type" == "alias" ]]; then
        add_alias "$name" "$command"
    else
        add_function "$name" "$command"
    fi
}

# Add alias
function add_alias() {
    local name="$1"
    local command="$2"
    
    if [[ -z "$command" ]]; then
        read_with_prompt "Enter command for alias '$name': " command
        if [[ -z "$command" ]]; then
            echo -e "${RED}Error:${NC} Command cannot be empty"
            return 1
        fi
    fi
    
    # Escape single quotes in command
    command=$(echo "$command" | sed "s/'/'\\\\''/g")
    
    # Create directory and file if needed
    mkdir -p "$(dirname "$ALIASES_FILE")"
    touch "$ALIASES_FILE"
    
    # Acquire lock before writing
    if ! acquire_aliases_lock; then
        return 1
    fi
    
    # Check disk space before writing (need space for backup + new content)
    if ! check_disk_space "$ALIASES_FILE" 2048; then
        release_aliases_lock
        return 1
    fi
    
    # Create backup before modifying file (with rotation)
    if [[ -f "$ALIASES_FILE" ]] && [[ -s "$ALIASES_FILE" ]]; then
        if ! create_backup_with_rotation "$ALIASES_FILE"; then
            release_aliases_lock
            echo -e "${RED}Error:${NC} Failed to create backup"
            return 1
        fi
    fi
    
    # Create temporary file for atomic write
    local temp_file=$(mktemp "$(dirname "$ALIASES_FILE")/aliases.XXXXXX" 2>/dev/null || mktemp)
    if [[ ! -f "$temp_file" ]]; then
        release_aliases_lock
        echo -e "${RED}Error:${NC} Failed to create temporary file"
        return 1
    fi
    # Register temp file for automatic cleanup
    register_temp_file "$temp_file"
    
    # Copy existing content to temp file (if file exists)
    if [[ -f "$ALIASES_FILE" ]] && [[ -s "$ALIASES_FILE" ]]; then
        if ! cp "$ALIASES_FILE" "$temp_file" 2>&1; then
            local copy_error=$?
            release_aliases_lock
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
            echo -e "${RED}Error:${NC} Failed to copy existing aliases to temporary file"
            echo "  Exit code: $copy_error"
            return 1
        fi
    fi
    
    # Append new alias to temp file with error checking
    if ! echo "alias $name='$command'" >> "$temp_file" 2>&1; then
        local write_error=$?
        release_aliases_lock
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        
        # Provide specific error messages based on common failure scenarios
        if [[ ! -w "$(dirname "$ALIASES_FILE")" ]] 2>/dev/null && [[ -d "$(dirname "$ALIASES_FILE")" ]]; then
            echo -e "${RED}Error:${NC} Permission denied - cannot write to directory: $(dirname "$ALIASES_FILE")"
        elif [[ -f "$temp_file" ]] && [[ ! -w "$temp_file" ]] 2>/dev/null; then
            echo -e "${RED}Error:${NC} Permission denied - cannot write to temporary file"
        else
            echo -e "${RED}Error:${NC} Failed to write alias to temporary file"
            echo "  This may be due to: disk full, permission issues, or filesystem errors"
            echo "  Exit code: $write_error"
        fi
        return 1
    fi
    
    # Validate temp file syntax before atomic replacement
    if ! bash -n "$temp_file" 2>/dev/null; then
        release_aliases_lock
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        echo -e "${RED}Error:${NC} Syntax error in alias definition - operation aborted"
        return 1
    fi
    
    # Atomically replace original file with temp file
    if ! mv "$temp_file" "$ALIASES_FILE" 2>&1; then
        local mv_error=$?
        release_aliases_lock
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        echo -e "${RED}Error:${NC} Failed to atomically replace aliases file"
        echo "  This may be due to: disk full, permission issues, or filesystem errors"
        echo "  Exit code: $mv_error"
        # Restore from backup if atomic replace failed
        if [[ -f "${ALIASES_FILE}.bak" ]]; then
            mv "${ALIASES_FILE}.bak" "$ALIASES_FILE" 2>/dev/null
            echo "  Original file restored from backup"
        fi
        return 1
    fi
    # Unregister temp file since it was successfully moved
    unregister_temp_file "$temp_file"
    
    # Release lock
    release_aliases_lock
    
    # Validate and source the file
    if ! bash -n "$ALIASES_FILE" 2>/dev/null; then
        echo -e "${RED}Error:${NC} Syntax error detected in aliases file after write"
        echo "  File may be corrupted. Check: $ALIASES_FILE"
        if [[ -f "${ALIASES_FILE}.bak" ]]; then
            echo "  Backup available at: ${ALIASES_FILE}.bak"
        fi
        return 1
    fi
    
    if source "$ALIASES_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Alias added: $name"
        echo "Saved to: $ALIASES_FILE"
    else
        echo -e "${RED}Error:${NC} Failed to source aliases file"
        echo "  This may indicate a syntax or runtime error"
        echo "  Check the file: $ALIASES_FILE"
        if [[ -f "${ALIASES_FILE}.bak" ]]; then
            echo "  Backup available at: ${ALIASES_FILE}.bak"
        fi
        return 1
    fi
}

# Add function
function add_function() {
    local name="$1"
    local command="$2"
    
    # Create directory and file if needed
    mkdir -p "$(dirname "$FUNCTIONS_FILE")"
    touch "$FUNCTIONS_FILE"
    
    if [[ -n "$command" ]]; then
        # Simple one-liner function
        # Acquire lock before writing
        if ! acquire_functions_lock; then
            return 1
        fi
        
        # Check disk space before writing (need space for backup + new content)
        if ! check_disk_space "$FUNCTIONS_FILE" 2048; then
            release_functions_lock
            return 1
        fi
        
        # Create backup before modifying file (with rotation)
        if [[ -f "$FUNCTIONS_FILE" ]] && [[ -s "$FUNCTIONS_FILE" ]]; then
            if ! create_backup_with_rotation "$FUNCTIONS_FILE"; then
                release_functions_lock
                echo -e "${RED}Error:${NC} Failed to create backup"
                return 1
            fi
        fi
        
        # Create temporary file for atomic write
        local temp_file=$(mktemp "$(dirname "$FUNCTIONS_FILE")/functions.XXXXXX" 2>/dev/null || mktemp)
        if [[ ! -f "$temp_file" ]]; then
            release_functions_lock
            echo -e "${RED}Error:${NC} Failed to create temporary file"
            return 1
        fi
        # Register temp file for automatic cleanup
        register_temp_file "$temp_file"
        
        # Copy existing content to temp file (if file exists)
        if [[ -f "$FUNCTIONS_FILE" ]] && [[ -s "$FUNCTIONS_FILE" ]]; then
            if ! cp "$FUNCTIONS_FILE" "$temp_file" 2>&1; then
                local copy_error=$?
                release_functions_lock
                unregister_temp_file "$temp_file"
                rm -f "$temp_file"
                echo -e "${RED}Error:${NC} Failed to copy existing functions to temporary file"
                echo "  Exit code: $copy_error"
                return 1
            fi
        fi
        
        # Append new function to temp file with error checking
        if ! {
            echo ""
            echo "function $name() {"
            echo "    $command"
            echo "}"
        } >> "$temp_file" 2>&1; then
            local write_error=$?
            release_functions_lock
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
            
            # Provide specific error messages based on common failure scenarios
            if [[ ! -w "$(dirname "$FUNCTIONS_FILE")" ]] 2>/dev/null && [[ -d "$(dirname "$FUNCTIONS_FILE")" ]]; then
                echo -e "${RED}Error:${NC} Permission denied - cannot write to directory: $(dirname "$FUNCTIONS_FILE")"
            elif [[ -f "$temp_file" ]] && [[ ! -w "$temp_file" ]] 2>/dev/null; then
                echo -e "${RED}Error:${NC} Permission denied - cannot write to temporary file"
            else
                echo -e "${RED}Error:${NC} Failed to write function to temporary file"
                echo "  This may be due to: disk full, permission issues, or filesystem errors"
                echo "  Exit code: $write_error"
            fi
            return 1
        fi
        
        # Validate temp file syntax before atomic replacement
        if ! bash -n "$temp_file" 2>/dev/null; then
            release_functions_lock
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
            echo -e "${RED}Error:${NC} Syntax error in function definition - operation aborted"
            return 1
        fi
        
        # Atomically replace original file with temp file
        if ! mv "$temp_file" "$FUNCTIONS_FILE" 2>&1; then
            local mv_error=$?
            release_functions_lock
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
            echo -e "${RED}Error:${NC} Failed to atomically replace functions file"
            echo "  This may be due to: disk full, permission issues, or filesystem errors"
            echo "  Exit code: $mv_error"
            # Restore from backup if atomic replace failed
            if [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
                mv "${FUNCTIONS_FILE}.bak" "$FUNCTIONS_FILE" 2>/dev/null
                echo "  Original file restored from backup"
            fi
            return 1
        fi
        # Unregister temp file since it was successfully moved
        unregister_temp_file "$temp_file"
        
        # Release lock
        release_functions_lock
        echo -e "${GREEN}✓${NC} Function added: $name"
    else
        # Open editor for complex function
        local temp_file=$(mktemp)
        # Register temp file for automatic cleanup
        register_temp_file "$temp_file"
        cat > "$temp_file" << EOF
function $name() {
    # TODO: Add your function code here
    echo "Function $name not implemented"
}
EOF
        
        # Store original checksum
        local original_checksum=""
        if command -v md5sum >/dev/null 2>&1; then
            original_checksum=$(md5sum "$temp_file" | cut -d' ' -f1)
        elif command -v md5 >/dev/null 2>&1; then
            original_checksum=$(md5 -q "$temp_file")
        fi
        
        # Open editor
        $EDITOR "$temp_file"
        
        # Check if file was modified
        local new_checksum=""
        if command -v md5sum >/dev/null 2>&1; then
            new_checksum=$(md5sum "$temp_file" | cut -d' ' -f1)
        elif command -v md5 >/dev/null 2>&1; then
            new_checksum=$(md5 -q "$temp_file")
        fi
        
        if [[ "$original_checksum" != "$new_checksum" ]] && [[ -s "$temp_file" ]]; then
            # Validate basic syntax
            if bash -n "$temp_file" 2>/dev/null; then
                # Acquire lock before writing
                if ! acquire_functions_lock; then
                    unregister_temp_file "$temp_file"
                    rm -f "$temp_file"
                    return 1
                fi
                
                # Check disk space before writing (need space for backup + new content)
                if ! check_disk_space "$FUNCTIONS_FILE" 2048; then
                    release_functions_lock
                    unregister_temp_file "$temp_file"
                    rm -f "$temp_file"
                    return 1
                fi
                
                # Create backup before modifying file (with rotation)
                if [[ -f "$FUNCTIONS_FILE" ]] && [[ -s "$FUNCTIONS_FILE" ]]; then
                    if ! create_backup_with_rotation "$FUNCTIONS_FILE"; then
                        release_functions_lock
                        unregister_temp_file "$temp_file"
                        rm -f "$temp_file"
                        echo -e "${RED}Error:${NC} Failed to create backup"
                        return 1
                    fi
                fi
                
                # Create temporary file for atomic write
                local atomic_temp_file=$(mktemp "$(dirname "$FUNCTIONS_FILE")/functions.XXXXXX" 2>/dev/null || mktemp)
                if [[ ! -f "$atomic_temp_file" ]]; then
                    release_functions_lock
                    unregister_temp_file "$temp_file"
                    rm -f "$temp_file"
                    echo -e "${RED}Error:${NC} Failed to create temporary file for atomic write"
                    return 1
                fi
                # Register atomic temp file for automatic cleanup
                register_temp_file "$atomic_temp_file"
                
                # Copy existing content to atomic temp file (if file exists)
                if [[ -f "$FUNCTIONS_FILE" ]] && [[ -s "$FUNCTIONS_FILE" ]]; then
                    if ! cp "$FUNCTIONS_FILE" "$atomic_temp_file" 2>&1; then
                        local copy_error=$?
                        release_functions_lock
                        unregister_temp_file "$temp_file"
                        unregister_temp_file "$atomic_temp_file"
                        rm -f "$temp_file" "$atomic_temp_file"
                        echo -e "${RED}Error:${NC} Failed to copy existing functions to temporary file"
                        echo "  Exit code: $copy_error"
                        return 1
                    fi
                fi
                
                # Append new function to atomic temp file with error checking
                if ! {
                    echo ""
                    cat "$temp_file"
                } >> "$atomic_temp_file" 2>&1; then
                    local write_error=$?
                    release_functions_lock
                    unregister_temp_file "$temp_file"
                    unregister_temp_file "$atomic_temp_file"
                    rm -f "$temp_file" "$atomic_temp_file"
                    
                    # Provide specific error messages based on common failure scenarios
                    if [[ ! -w "$(dirname "$FUNCTIONS_FILE")" ]] 2>/dev/null && [[ -d "$(dirname "$FUNCTIONS_FILE")" ]]; then
                        echo -e "${RED}Error:${NC} Permission denied - cannot write to directory: $(dirname "$FUNCTIONS_FILE")"
                    elif [[ -f "$atomic_temp_file" ]] && [[ ! -w "$atomic_temp_file" ]] 2>/dev/null; then
                        echo -e "${RED}Error:${NC} Permission denied - cannot write to temporary file"
                    else
                        echo -e "${RED}Error:${NC} Failed to write function to temporary file"
                        echo "  This may be due to: disk full, permission issues, or filesystem errors"
                        echo "  Exit code: $write_error"
                    fi
                    return 1
                fi
                
                # Validate atomic temp file syntax before atomic replacement
                if ! bash -n "$atomic_temp_file" 2>/dev/null; then
                    release_functions_lock
                    unregister_temp_file "$temp_file"
                    unregister_temp_file "$atomic_temp_file"
                    rm -f "$temp_file" "$atomic_temp_file"
                    echo -e "${RED}Error:${NC} Syntax error in function definition - operation aborted"
                    return 1
                fi
                
                # Atomically replace original file with atomic temp file
                if ! mv "$atomic_temp_file" "$FUNCTIONS_FILE" 2>&1; then
                    local mv_error=$?
                    release_functions_lock
                    unregister_temp_file "$temp_file"
                    unregister_temp_file "$atomic_temp_file"
                    rm -f "$temp_file" "$atomic_temp_file"
                    echo -e "${RED}Error:${NC} Failed to atomically replace functions file"
                    echo "  This may be due to: disk full, permission issues, or filesystem errors"
                    echo "  Exit code: $mv_error"
                    # Restore from backup if atomic replace failed
                    if [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
                        mv "${FUNCTIONS_FILE}.bak" "$FUNCTIONS_FILE" 2>/dev/null
                        echo "  Original file restored from backup"
                    fi
                    return 1
                fi
                # Unregister atomic temp file since it was successfully moved
                unregister_temp_file "$atomic_temp_file"
                
                # Release lock
                release_functions_lock
                echo -e "${GREEN}✓${NC} Function added: $name"
                
                # Show preview
                echo -e "${CYAN}Preview:${NC}"
                cat "$temp_file" | head -10
                if [[ $(wc -l < "$temp_file") -gt 10 ]]; then
                    echo "..."
                fi
                # Unregister and remove editor temp file
                unregister_temp_file "$temp_file"
                rm -f "$temp_file"
            else
                echo -e "${RED}Error:${NC} Syntax error in function definition"
                echo "Function not added."
                unregister_temp_file "$temp_file"
                rm -f "$temp_file"
                return 1
            fi
        else
            echo "Function creation cancelled."
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
        fi
    fi
    
    # Validate and source the file
    if ! bash -n "$FUNCTIONS_FILE" 2>/dev/null; then
        echo -e "${RED}Error:${NC} Syntax error detected in functions file after write"
        echo "  File may be corrupted. Check: $FUNCTIONS_FILE"
        if [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
            echo "  Backup available at: ${FUNCTIONS_FILE}.bak"
        fi
        return 1
    fi
    
    if source "$FUNCTIONS_FILE" 2>/dev/null; then
        echo "Saved to: $FUNCTIONS_FILE"
    else
        echo -e "${RED}Error:${NC} Failed to source functions file"
        echo "  This may indicate a syntax or runtime error"
        echo "  Check the file: $FUNCTIONS_FILE"
        if [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
            echo "  Backup available at: ${FUNCTIONS_FILE}.bak"
        fi
        return 1
    fi
}

# List command
function am_list() {
    local show_aliases=true
    local show_functions=true
    local show_commands=false
    local search_name=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--aliases)
                show_functions=false
                shift
                ;;
            -f|--functions)
                show_aliases=false
                shift
                ;;
            -c|--commands)
                show_commands=true
                shift
                ;;
            -h|--help)
                am_list_help
                return 0
                ;;
            *)
                search_name="$1"
                shift
                ;;
        esac
    done
    
    # If searching for specific name
    if [[ -n "$search_name" ]]; then
        search_definition "$search_name"
        return $?
    fi
    
    local has_output=false
    
    # List aliases
    if [[ "$show_aliases" == true ]]; then
        if [[ -f "$ALIASES_FILE" ]] && grep -q "^alias " "$ALIASES_FILE" 2>/dev/null; then
            echo -e "${BLUE}=== Aliases ===${NC}"
            if [[ "$show_commands" == true ]]; then
                grep "^alias " "$ALIASES_FILE" 2>/dev/null | sed 's/^alias //' | sort | while IFS='=' read -r name cmd; do
                    printf "%-20s %s\n" "$name" "$cmd"
                done
            else
                grep "^alias " "$ALIASES_FILE" 2>/dev/null | sed 's/^alias //' | cut -d'=' -f1 | sort
            fi
            echo
            has_output=true
        fi
    fi
    
    # List functions
    if [[ "$show_functions" == true ]]; then
        if [[ -f "$FUNCTIONS_FILE" ]]; then
            local func_names=$(grep -E "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null | \
                sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/' | \
                sort | uniq)
            if [[ -n "$func_names" ]]; then
                echo -e "${PURPLE}=== Functions ===${NC}"
                echo "$func_names"
                echo
                has_output=true
            fi
        fi
    fi
    
    # Show message if nothing was found
    if [[ "$has_output" == false ]]; then
        if [[ "$show_aliases" == true ]] && [[ "$show_functions" == true ]]; then
            echo "No aliases or functions found."
        elif [[ "$show_aliases" == true ]]; then
            echo "No aliases found."
        elif [[ "$show_functions" == true ]]; then
            echo "No functions found."
        fi
    fi
}

# Path/show command - display file paths and optionally open them
function am_path() {
    local open_file=false
    local show_aliases=true
    local show_functions=true
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--open)
                open_file=true
                shift
                ;;
            -a|--aliases)
                show_functions=false
                shift
                ;;
            -f|--functions)
                show_aliases=false
                shift
                ;;
            -h|--help)
                am_path_help
                return 0
                ;;
            *)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                echo "Use 'am path --help' for usage information"
                return 1
                ;;
        esac
    done
    
    # Show aliases file path
    if [[ "$show_aliases" == true ]]; then
        echo -e "${BLUE}Aliases file:${NC} $ALIASES_FILE"
        if [[ -f "$ALIASES_FILE" ]]; then
            local alias_count=$(grep -c "^alias " "$ALIASES_FILE" 2>/dev/null || echo 0)
            alias_count=${alias_count:-0}
            if [[ "$alias_count" -gt 0 ]] 2>/dev/null; then
                echo "  Contains $alias_count alias(es)"
            else
                echo "  File exists but is empty"
            fi
        else
            echo "  File does not exist (will be created on first add)"
        fi
        
        # Open aliases file if requested
        if [[ "$open_file" == true ]]; then
            if [[ -f "$ALIASES_FILE" ]] || [[ -d "$(dirname "$ALIASES_FILE")" ]]; then
                # Create file if it doesn't exist
                if [[ ! -f "$ALIASES_FILE" ]]; then
                    mkdir -p "$(dirname "$ALIASES_FILE")"
                    touch "$ALIASES_FILE"
                fi
                # Open with editor
                if command -v "$EDITOR" >/dev/null 2>&1; then
                    echo "  Opening with: $EDITOR"
                    "$EDITOR" "$ALIASES_FILE"
                else
                    echo -e "  ${YELLOW}Warning:${NC} Editor '$EDITOR' not found. Trying default editor..."
                    if command -v vi >/dev/null 2>&1; then
                        vi "$ALIASES_FILE"
                    elif command -v nano >/dev/null 2>&1; then
                        nano "$ALIASES_FILE"
                    else
                        echo -e "  ${RED}Error:${NC} No suitable editor found"
                        return 1
                    fi
                fi
            else
                echo -e "  ${RED}Error:${NC} Cannot create file or directory"
                return 1
            fi
        fi
        echo
    fi
    
    # Show functions file path
    if [[ "$show_functions" == true ]]; then
        echo -e "${PURPLE}Functions file:${NC} $FUNCTIONS_FILE"
        if [[ -f "$FUNCTIONS_FILE" ]]; then
            local func_count=$(grep -E -c "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null || echo 0)
            func_count=${func_count:-0}
            if [[ "$func_count" -gt 0 ]] 2>/dev/null; then
                echo "  Contains $func_count function(s)"
            else
                echo "  File exists but is empty"
            fi
        else
            echo "  File does not exist (will be created on first add)"
        fi
        
        # Open functions file if requested
        if [[ "$open_file" == true ]]; then
            if [[ -f "$FUNCTIONS_FILE" ]] || [[ -d "$(dirname "$FUNCTIONS_FILE")" ]]; then
                # Create file if it doesn't exist
                if [[ ! -f "$FUNCTIONS_FILE" ]]; then
                    mkdir -p "$(dirname "$FUNCTIONS_FILE")"
                    touch "$FUNCTIONS_FILE"
                fi
                # Open with editor
                if command -v "$EDITOR" >/dev/null 2>&1; then
                    echo "  Opening with: $EDITOR"
                    "$EDITOR" "$FUNCTIONS_FILE"
                else
                    echo -e "  ${YELLOW}Warning:${NC} Editor '$EDITOR' not found. Trying default editor..."
                    if command -v vi >/dev/null 2>&1; then
                        vi "$FUNCTIONS_FILE"
                    elif command -v nano >/dev/null 2>&1; then
                        nano "$FUNCTIONS_FILE"
                    else
                        echo -e "  ${RED}Error:${NC} No suitable editor found"
                        return 1
                    fi
                fi
            else
                echo -e "  ${RED}Error:${NC} Cannot create file or directory"
                return 1
            fi
        fi
        echo
    fi
}

# Search for specific definition
function search_definition() {
    local name="$1"
    local found=false
    local escaped_name=$(escape_regex_special "$name")
    
    # Check aliases
    if [[ -f "$ALIASES_FILE" ]] && grep -q "^alias $escaped_name=" "$ALIASES_FILE" 2>/dev/null; then
        echo -e "${BLUE}Alias '$name':${NC}"
        grep "^alias $escaped_name=" "$ALIASES_FILE" | head -1
        found=true
    fi
    
    # Check functions
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        # Use sed to extract function (more reliable than awk for nested braces)
        local func_def=$(sed -n "/^[[:space:]]*function[[:space:]]\+$escaped_name[[:space:]]*(/,/^}/p; /^[[:space:]]*$escaped_name[[:space:]]*()[[:space:]]*{/,/^}/p" "$FUNCTIONS_FILE" 2>/dev/null | head -20)
        if [[ -n "$func_def" ]]; then
            if [[ "$found" == true ]]; then
                echo ""  # Add spacing between alias and function
            fi
            echo -e "${PURPLE}Function '$name':${NC}"
            echo "$func_def"
            found=true
        fi
    fi
    
    if [[ "$found" != true ]]; then
        echo -e "${RED}Error:${NC} No alias or function named '$name' found"
        return 1
    fi
}

# Install command - setup auto-sourcing in shell config files
function am_install() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_install_help
        return 0
    fi
    
    local force=false
    local shell_type=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                force=true
                shift
                ;;
            --shell)
                shell_type="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                echo "Use 'am install --help' for usage information"
                return 1
                ;;
        esac
    done
    
    # Detect shell type - check user's default shell, not current shell
    if [[ -z "$shell_type" ]]; then
        # First, check $SHELL environment variable (user's default shell)
        if [[ -n "$SHELL" ]]; then
            if [[ "$SHELL" == *"zsh"* ]]; then
                shell_type="zsh"
            elif [[ "$SHELL" == *"bash"* ]]; then
                shell_type="bash"
            fi
        fi
        
        # If still not determined, check for existing config files
        if [[ -z "$shell_type" ]]; then
            if [[ -f "$HOME/.zshrc" ]]; then
                shell_type="zsh"
            elif [[ -f "$HOME/.bashrc" ]] || [[ -f "$HOME/.bash_profile" ]]; then
                shell_type="bash"
            fi
        fi
        
        # If still not determined, try to get from /etc/passwd
        if [[ -z "$shell_type" ]]; then
            local user_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")
            if [[ "$user_shell" == *"zsh"* ]]; then
                shell_type="zsh"
            elif [[ "$user_shell" == *"bash"* ]]; then
                shell_type="bash"
            fi
        fi
        
        # Default to bash if still not determined
        if [[ -z "$shell_type" ]]; then
            shell_type="bash"
        fi
    fi
    
    # Show detected shell type
    echo -e "${CYAN}Detected shell:${NC} $shell_type"
    if [[ -n "$SHELL" ]]; then
        echo -e "  Default shell: $SHELL"
    fi
    echo
    
    # Determine config file based on shell
    local config_file=""
    case "$shell_type" in
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                config_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                config_file="$HOME/.bash_profile"
            else
                config_file="$HOME/.bashrc"
            fi
            ;;
        zsh)
            config_file="$HOME/.zshrc"
            ;;
        *)
            echo -e "${RED}Error:${NC} Unsupported shell type: $shell_type"
            echo "Supported shells: bash, zsh"
            return 1
            ;;
    esac
    
    # Create sourcing snippet
    local source_snippet="# Alias Manager - Auto-sourced aliases and functions
if [[ -f \"$ALIASES_FILE\" ]]; then
    source \"$ALIASES_FILE\"
fi
if [[ -f \"$FUNCTIONS_FILE\" ]]; then
    source \"$FUNCTIONS_FILE\"
fi"
    
    # Check if already installed
    if grep -q "Alias Manager - Auto-sourced" "$config_file" 2>/dev/null; then
        if [[ "$force" == false ]]; then
            echo -e "${YELLOW}Alias Manager is already installed in $config_file${NC}"
            echo "Use --force to reinstall"
            return 0
        else
            # Remove old installation
            sed -i.bak "/# Alias Manager - Auto-sourced/,/fi$/d" "$config_file" 2>/dev/null || \
            sed -i "/# Alias Manager - Auto-sourced/,/fi$/d" "$config_file" 2>/dev/null
        fi
    fi
    
    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        mkdir -p "$(dirname "$config_file")"
        touch "$config_file"
    fi
    
    # Append sourcing snippet
    echo "" >> "$config_file"
    echo "$source_snippet" >> "$config_file"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} Alias Manager installed successfully in $config_file"
        echo "  Aliases and functions will be automatically sourced in new shell sessions"
        echo "  Run 'source $config_file' to apply changes to current session"
        return 0
    else
        echo -e "${RED}Error:${NC} Failed to install Alias Manager"
        return 1
    fi
}

# Status command - check installation and sourcing status
function am_status() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_status_help
        return 0
    fi
    
    echo -e "${CYAN}=== Alias Manager Status ===${NC}"
    echo
    
    # Check file locations
    echo -e "${YELLOW}File Locations:${NC}"
    echo "  Aliases:   $ALIASES_FILE"
    if [[ -f "$ALIASES_FILE" ]]; then
        local alias_count=$(grep -c "^alias " "$ALIASES_FILE" 2>/dev/null || echo 0)
        echo -e "    ${GREEN}✓${NC} Exists ($alias_count aliases)"
    else
        echo -e "    ${YELLOW}⚠${NC} Does not exist (will be created on first add)"
    fi
    
    echo "  Functions: $FUNCTIONS_FILE"
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        local func_count=0
        if grep -qE "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null; then
            func_count=$(grep -E -c "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null)
            func_count=${func_count:-0}
        fi
        echo -e "    ${GREEN}✓${NC} Exists ($func_count functions)"
    else
        echo -e "    ${YELLOW}⚠${NC} Does not exist (will be created on first add)"
    fi
    echo
    
    # Check installation status
    echo -e "${YELLOW}Installation Status:${NC}"
    local installed=false
    local config_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile")
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]] && grep -q "Alias Manager - Auto-sourced" "$config_file" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Installed in $config_file"
            installed=true
        fi
    done
    
    if [[ "$installed" == false ]]; then
        echo -e "  ${YELLOW}⚠${NC} Not installed"
        echo "    Run 'am install' to setup auto-sourcing"
    fi
    echo
    
    # Check if files are sourced in current session
    echo -e "${YELLOW}Current Session:${NC}"
    local aliases_sourced=false
    local functions_sourced=false
    local can_verify=true
    
    # Check if we're running in a subprocess (bash am.sh vs sourced am)
    # If BASH_SOURCE[0] is set and we're being executed directly, we're in a subprocess
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]] || [[ "$0" == *"am.sh"* ]]; then
        # We're running as a script, so we're in a new process
        # Can't verify aliases from parent shell, but we can still try
        can_verify=false
    fi
    
    if [[ -f "$ALIASES_FILE" ]]; then
        # Get first few aliases from our file to test
        local test_aliases=$(grep "^alias " "$ALIASES_FILE" 2>/dev/null | head -5 | sed 's/^alias //' | cut -d'=' -f1)
        local found_count=0
        local total_checked=0
        
        if [[ -n "$test_aliases" ]]; then
            while IFS= read -r alias_name; do
                if [[ -n "$alias_name" ]]; then
                    ((total_checked++))
                    # Check if this alias exists and is actually an alias
                    # Use 'command -v' as fallback for shells that don't support 'type -t'
                    local alias_type=""
                    if command -v type >/dev/null 2>&1; then
                        alias_type=$(type -t "$alias_name" 2>/dev/null || echo "")
                    fi
                    
                    # If type -t doesn't work or returns nothing, try alias command
                    if [[ -z "$alias_type" ]]; then
                        if alias "$alias_name" >/dev/null 2>&1; then
                            alias_type="alias"
                        fi
                    fi
                    
                    if [[ "$alias_type" == "alias" ]]; then
                        # Get the current alias definition
                        local current_alias_def=$(alias "$alias_name" 2>/dev/null | sed 's/^alias //' | head -1)
                        # Get our alias definition from file
                        local our_alias_line=$(grep "^alias $alias_name=" "$ALIASES_FILE" 2>/dev/null | head -1)
                        local our_alias_def=$(echo "$our_alias_line" | sed 's/^alias //')
                        
                        # If we have both definitions, consider it a match
                        # (exact matching is tricky due to quote differences, so we'll be lenient)
                        if [[ -n "$current_alias_def" ]] && [[ -n "$our_alias_def" ]]; then
                            # Extract just the command part (after =)
                            local current_cmd=$(echo "$current_alias_def" | sed "s/^$alias_name=//; s/^['\"]//; s/['\"]$//")
                            local our_cmd=$(echo "$our_alias_def" | sed "s/^$alias_name=//; s/^['\"]//; s/['\"]$//")
                            
                            # If commands match (allowing for quote differences), it's sourced
                            if [[ "$current_cmd" == "$our_cmd" ]] || [[ -n "$current_cmd" ]]; then
                                ((found_count++))
                            fi
                        elif [[ -n "$current_alias_def" ]]; then
                            # If alias exists, it might be sourced (even if we can't verify exact match)
                            ((found_count++))
                        fi
                    fi
                fi
            done <<< "$test_aliases"
        fi
        
        # If we found at least one matching alias, consider it sourced
        if [[ $found_count -gt 0 ]]; then
            aliases_sourced=true
        fi
    fi
    
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        # Check if any functions from our file are available
        local test_functions=$(grep -E "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null | \
            head -5 | sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/')
        
        local func_found_count=0
        if [[ -n "$test_functions" ]]; then
            while IFS= read -r func_name; do
                if [[ -n "$func_name" ]]; then
                    local func_type=""
                    if command -v type >/dev/null 2>&1; then
                        func_type=$(type -t "$func_name" 2>/dev/null || echo "")
                    fi
                    if [[ "$func_type" == "function" ]] || declare -f "$func_name" >/dev/null 2>&1; then
                        ((func_found_count++))
                    fi
                fi
            done <<< "$test_functions"
        fi
        
        if [[ $func_found_count -gt 0 ]]; then
            functions_sourced=true
        fi
    fi
    
    if [[ "$aliases_sourced" == true ]] || [[ "$functions_sourced" == true ]]; then
        echo -e "  ${GREEN}✓${NC} Files are sourced in current session"
        if [[ "$aliases_sourced" == true ]]; then
            echo "    Aliases: loaded"
        fi
        if [[ "$functions_sourced" == true ]]; then
            echo "    Functions: loaded"
        fi
    elif [[ "$can_verify" == false ]]; then
        # Running as a script in a subprocess - can't verify parent shell's aliases
        if [[ -f "$ALIASES_FILE" ]] || [[ -f "$FUNCTIONS_FILE" ]]; then
            echo -e "  ${BLUE}[INFO]${NC} Cannot verify (running in new shell process)"
            echo "    If installed via 'am install', aliases load automatically in new sessions"
            echo "    To verify in current shell: source am.sh && am status"
        fi
    else
        if [[ -f "$ALIASES_FILE" ]] || [[ -f "$FUNCTIONS_FILE" ]]; then
            echo -e "  ${YELLOW}⚠${NC} Files do not appear to be sourced"
            if [[ -f "$ALIASES_FILE" ]]; then
                echo "    Run 'source $ALIASES_FILE' to load aliases"
            fi
            if [[ -f "$FUNCTIONS_FILE" ]]; then
                echo "    Run 'source $FUNCTIONS_FILE' to load functions"
            fi
        else
            echo -e "  ${YELLOW}⚠${NC} No files to check"
        fi
    fi
    echo
    
    # Statistics
    echo -e "${YELLOW}Statistics:${NC}"
    local total_aliases=0
    local total_functions=0
    
    if [[ -f "$ALIASES_FILE" ]]; then
        total_aliases=$(grep -c "^alias " "$ALIASES_FILE" 2>/dev/null || echo 0)
    fi
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        if grep -qE "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null; then
            total_functions=$(grep -E -c "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null)
            total_functions=${total_functions:-0}
        else
            total_functions=0
        fi
    fi
    
    echo "  Total aliases:   $total_aliases"
    echo "  Total functions: $total_functions"
    echo "  Total items:     $((total_aliases + total_functions))"
}

# Search command - search aliases and functions
function am_search() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_search_help
        return 0
    fi
    
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error:${NC} Search pattern is required"
        echo "Use 'am search --help' for usage information"
        return 1
    fi
    
    local pattern="$1"
    local search_aliases=true
    local search_functions=true
    local search_commands=false
    
    # Parse arguments
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--aliases)
                search_functions=false
                shift
                ;;
            -f|--functions)
                search_aliases=false
                shift
                ;;
            -c|--commands)
                search_commands=true
                shift
                ;;
            *)
                echo -e "${RED}Error:${NC} Unknown option: $1"
                echo "Use 'am search --help' for usage information"
                return 1
                ;;
        esac
    done
    
    local found=false
    
    # Search aliases
    if [[ "$search_aliases" == true ]] && [[ -f "$ALIASES_FILE" ]]; then
        local alias_matches=$(grep -i "^alias " "$ALIASES_FILE" 2>/dev/null | grep -i "$pattern")
        if [[ -n "$alias_matches" ]]; then
            echo -e "${BLUE}=== Matching Aliases ===${NC}"
            echo "$alias_matches" | while IFS= read -r line; do
                if [[ "$search_commands" == true ]]; then
                    echo "$line"
                else
                    echo "$line" | sed 's/^alias //' | cut -d'=' -f1
                fi
            done
            echo
            found=true
        fi
    fi
    
    # Search functions
    if [[ "$search_functions" == true ]] && [[ -f "$FUNCTIONS_FILE" ]]; then
        # Search function names
        local func_name_matches=$(grep -iE "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null | \
            grep -i "$pattern" | \
            sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/')
        
        # Search function bodies if --commands is used
        if [[ "$search_commands" == true ]]; then
            local func_body_matches=$(grep -i "$pattern" "$FUNCTIONS_FILE" 2>/dev/null)
        fi
        
        if [[ -n "$func_name_matches" ]] || ([[ "$search_commands" == true ]] && [[ -n "$func_body_matches" ]]); then
            echo -e "${PURPLE}=== Matching Functions ===${NC}"
            if [[ "$search_commands" == true ]] && [[ -n "$func_body_matches" ]]; then
                echo "$func_body_matches"
            else
                echo "$func_name_matches" | sort | uniq
            fi
            echo
            found=true
        fi
    fi
    
    if [[ "$found" == false ]]; then
        echo "No matches found for pattern: $pattern"
        return 1
    fi
    
    return 0
}

# Edit command - edit an existing alias or function
function am_edit() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_edit_help
        return 0
    fi
    
    if [[ $# -eq 0 ]]; then
        echo -e "${RED}Error:${NC} Name is required"
        echo "Use 'am edit --help' for usage information"
        return 1
    fi
    
    local name="$1"
    local type=""
    
    # Determine type
    if check_alias_exists "$name" | grep -q "true"; then
        type="alias"
    elif check_function_exists "$name" | grep -q "true"; then
        type="function"
    else
        echo -e "${RED}Error:${NC} '$name' not found as alias or function"
        return 1
    fi
    
    if [[ "$type" == "alias" ]]; then
        # Get current alias definition
        local current_def=$(get_alias_definition "$name")
        if [[ -z "$current_def" ]]; then
            echo -e "${RED}Error:${NC} Could not retrieve alias definition"
            return 1
        fi
        
        # Create temp file with current definition
        local temp_file=$(mktemp)
        echo "$current_def" > "$temp_file"
        register_temp_file "$temp_file"
        
        # Open in editor
        if command -v "$EDITOR" >/dev/null 2>&1; then
            "$EDITOR" "$temp_file"
        else
            echo -e "${RED}Error:${NC} Editor '$EDITOR' not found"
            unregister_temp_file "$temp_file"
            rm -f "$temp_file"
            return 1
        fi
        
        # Read edited definition
        local edited_def=$(cat "$temp_file")
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        
        # Validate and update
        if [[ -z "$edited_def" ]]; then
            echo -e "${RED}Error:${NC} Empty definition"
            return 1
        fi
        
        # Extract command from edited definition
        local new_cmd=$(echo "$edited_def" | sed "s/^alias $name='//; s/'$//")
        
        # Remove old and add new
        am_remove --force -a "$name" >/dev/null 2>&1
        am_add -a "$name" "$new_cmd"
    else
        # For functions, we need to edit the function file
        # This is more complex, so we'll open the functions file and highlight the function
        if [[ ! -f "$FUNCTIONS_FILE" ]]; then
            echo -e "${RED}Error:${NC} Functions file not found"
            return 1
        fi
        
        # Open functions file in editor
        if command -v "$EDITOR" >/dev/null 2>&1; then
            echo "Opening functions file. Please locate and edit function '$name'"
            "$EDITOR" "$FUNCTIONS_FILE"
            echo -e "${GREEN}✓${NC} Functions file edited"
            echo "  Run 'source $FUNCTIONS_FILE' to reload functions"
        else
            echo -e "${RED}Error:${NC} Editor '$EDITOR' not found"
            return 1
        fi
    fi
}

# Update command - update an existing alias or function
function am_update() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_update_help
        return 0
    fi
    
    if [[ $# -lt 2 ]]; then
        echo -e "${RED}Error:${NC} Name and command are required"
        echo "Use 'am update --help' for usage information"
        return 1
    fi
    
    local name="$1"
    shift
    local command="$*"
    
    if [[ -z "$command" ]]; then
        echo -e "${RED}Error:${NC} Command cannot be empty"
        return 1
    fi
    
    # Determine type
    local type=""
    local type_flag=""
    
    if check_alias_exists "$name" | grep -q "true"; then
        type="alias"
        type_flag="-a"
    elif check_function_exists "$name" | grep -q "true"; then
        type="function"
        type_flag="-f"
    else
        echo -e "${RED}Error:${NC} '$name' not found as alias or function"
        echo "Use 'am add' to create a new alias or function"
        return 1
    fi
    
    # Remove old and add new with force
    am_remove --force $type_flag "$name" >/dev/null 2>&1
    am_add $type_flag "$name" "$command"
}

# Remove command
function am_remove() {
    local name=""
    local type=""
    local force=false
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--alias)
                type="alias"
                shift
                ;;
            -f|--function)
                type="function"
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                am_remove_help
                return 0
                ;;
            *)
                name="$1"
                shift
                ;;
        esac
    done
    
    if [[ -z "$name" ]]; then
        echo -e "${RED}Error:${NC} Name is required"
        echo "Use 'am rm --help' for usage information"
        return 1
    fi
    
    # Check where it exists
    local exists_in_aliases=$(check_alias_exists "$name")
    local exists_in_functions=$(check_function_exists "$name")
    
     # If it doesn't exist anywhere
    if [[ "$exists_in_aliases" != "true" && "$exists_in_functions" != "true" ]]; then
        echo -e "${RED}Error:${NC} No alias or function named '$name' found"
        return 1
    fi
    
    # Handle duplicates
    if [[ "$exists_in_aliases" == "true" && "$exists_in_functions" == "true" && -z "$type" ]]; then
        echo -e "${YELLOW}Warning:${NC} Found both alias and function named '$name'"
        echo -e "  ${BLUE}Alias:${NC} $(get_alias_definition "$name")"
        echo -e "  ${PURPLE}Function:${NC} $(get_function_summary "$name")"
        echo ""
        echo "Which would you like to remove?"
        echo "1) Alias"
        echo "2) Function"
        echo "3) Both"
        echo "4) Cancel"
        read_with_prompt "Choice (1-4): " -n 1 response
        echo
        case $response in
            1) type="alias" ;;
            2) type="function" ;;
            3) type="both" ;;
            *) echo "Cancelled."; return 0 ;;
        esac
    fi
    
    # Confirm removal
    if [[ "$force" != true ]]; then
        local prompt=""
        if [[ "$type" == "both" ]]; then
            prompt="Remove both alias and function '$name'?"
        elif [[ "$type" == "alias" || "$exists_in_aliases" == "true" ]]; then
            prompt="Remove alias '$name'?"
        else
            prompt="Remove function '$name'?"
        fi
        read_with_prompt "$prompt (y/N): " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
    fi
    
    # Remove based on type with transaction-like behavior
    local remove_alias_needed=false
    local remove_function_needed=false
    local alias_removed=false
    local function_removed=false
    local alias_backup=""
    local function_backup=""
    
    # Determine what needs to be removed
    if [[ "$type" == "alias" || "$type" == "both" || (-z "$type" && "$exists_in_aliases" == "true") ]]; then
        remove_alias_needed=true
    fi
    
    if [[ "$type" == "function" || "$type" == "both" || (-z "$type" && "$exists_in_functions" == "true") ]]; then
        remove_function_needed=true
    fi
    
    # Handle dry-run mode
    if [[ "$dry_run" == true ]]; then
        echo -e "${CYAN}[DRY RUN]${NC} Would remove:"
        if [[ "$remove_alias_needed" == true ]]; then
            echo -e "  ${BLUE}Alias:${NC} $name"
            if [[ -f "$ALIASES_FILE" ]]; then
                local alias_def=$(get_alias_definition "$name")
                [[ -n "$alias_def" ]] && echo "    Definition: $alias_def"
            fi
        fi
        if [[ "$remove_function_needed" == true ]]; then
            echo -e "  ${PURPLE}Function:${NC} $name"
        fi
        return 0
    fi
    
    # If removing both, we need transaction-like behavior
    if [[ "$remove_alias_needed" == true && "$remove_function_needed" == true ]]; then
        # Create backups before any removal
        if [[ -f "$ALIASES_FILE" ]] && [[ -f "${ALIASES_FILE}.bak" ]]; then
            alias_backup="${ALIASES_FILE}.bak"
        fi
        if [[ -f "$FUNCTIONS_FILE" ]] && [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
            function_backup="${FUNCTIONS_FILE}.bak"
        fi
        
        # Try to remove alias first
        if remove_alias "$name"; then
            alias_removed=true
        else
            echo -e "${RED}Error:${NC} Failed to remove alias '$name'"
            return 1
        fi
        
        # Try to remove function
        if remove_function "$name"; then
            function_removed=true
        else
            # Rollback: restore alias if function removal failed
            echo -e "${YELLOW}Warning:${NC} Function removal failed - rolling back alias removal"
            if [[ -f "$alias_backup" ]]; then
                cp "$alias_backup" "$ALIASES_FILE" 2>/dev/null
                echo "  Alias restored from backup"
            fi
            return 1
        fi
    else
        # Single removal - no transaction needed
        if [[ "$remove_alias_needed" == true ]]; then
            remove_alias "$name"
        fi
        
        if [[ "$remove_function_needed" == true ]]; then
            remove_function "$name"
        fi
    fi
}

# Remove alias
function remove_alias() {
    local name="$1"
    if [[ ! -f "$ALIASES_FILE" ]]; then
        return 1
    fi

    # Acquire lock before modifying
    if ! acquire_aliases_lock; then
        return 1
    fi

    # Check disk space before modifying (need space for backup + temp file)
    if ! check_disk_space "$ALIASES_FILE" 2048; then
        release_aliases_lock
        return 1
    fi

    # Create backup with rotation
    if ! create_backup_with_rotation "$ALIASES_FILE"; then
        release_aliases_lock
        echo -e "${RED}Error:${NC} Failed to create backup"
        return 1
    fi

    # Remove the alias using sed (more reliable than grep -v)
    # Use sed to delete lines matching the pattern, handling empty files correctly
    local escaped_name=$(escape_regex_special "$name")
    if sed "/^alias $escaped_name=/d" "$ALIASES_FILE" > "$ALIASES_FILE.tmp" 2>/dev/null; then
        if mv "$ALIASES_FILE.tmp" "$ALIASES_FILE"; then
            release_aliases_lock
            echo -e "${GREEN}✓${NC} Alias '$name' removed"
            echo "Backup saved to: ${ALIASES_FILE}.bak"
        else
            # Restore from backup if mv failed
            if [[ -f "${ALIASES_FILE}.bak" ]]; then
                mv "${ALIASES_FILE}.bak" "$ALIASES_FILE" 2>/dev/null
                echo -e "${YELLOW}Warning:${NC} Failed to update aliases file - restored from backup"
            fi
            release_aliases_lock
            rm -f "$ALIASES_FILE.tmp"
            echo -e "${RED}Error:${NC} Failed to update aliases file"
            return 1
        fi
    else
        release_aliases_lock
        echo -e "${RED}Error:${NC} Failed to remove alias"
        return 1
    fi
}

# Remove function
function remove_function() {
    local name="$1"
    
    if [[ ! -f "$FUNCTIONS_FILE" ]]; then
        return 1
    fi
    
    # Acquire lock before modifying
    if ! acquire_functions_lock; then
        return 1
    fi
    
    # Check disk space before modifying (need space for backup + temp file)
    if ! check_disk_space "$FUNCTIONS_FILE" 2048; then
        release_functions_lock
        return 1
    fi
    
    # Create backup with rotation
    if ! create_backup_with_rotation "$FUNCTIONS_FILE"; then
        release_functions_lock
        echo -e "${RED}Error:${NC} Failed to create backup"
        return 1
    fi
    
    # Create a temporary file
    local temp_file=$(mktemp)
    if [[ ! -f "$temp_file" ]]; then
        release_functions_lock
        echo -e "${RED}Error:${NC} Failed to create temporary file"
        return 1
    fi
    # Register temp file for automatic cleanup
    register_temp_file "$temp_file"
    
    local in_function=false
    local brace_count=0
    local write_failed=false
    local in_string=false
    local string_char=""
    
    # Escape function name for regex matching
    local escaped_name=$(escape_regex_special "$name")
    
    # Process file line by line to handle nested braces
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if we're starting the target function
        if [[ "$line" =~ ^[[:space:]]*(function[[:space:]]+${escaped_name}[[:space:]]*\(|${escaped_name}[[:space:]]*\()[[:space:]]*\{? ]]; then
            in_function=true
            brace_count=0
            in_string=false
            string_char=""
        fi
        
        # If we're in the target function, count braces (ignoring strings and comments)
        if [[ "$in_function" == true ]]; then
            # Remove comments (everything after # that's not in a string)
            local processed_line="$line"
            if [[ ! "$in_string" == true ]]; then
                # Remove comment portion (simple approach - may miss edge cases)
                processed_line=$(echo "$line" | sed 's/#.*$//')
            fi
            
            # Process character by character to handle strings
            local i=0
            while [[ $i -lt ${#processed_line} ]]; do
                local char="${processed_line:$i:1}"
                local prev_char=""
                [[ $i -gt 0 ]] && prev_char="${processed_line:$((i-1)):1}"
                
                # Handle string boundaries (account for escaped quotes)
                if [[ "$char" == "'" || "$char" == '"' ]]; then
                    if [[ "$in_string" == false ]]; then
                        in_string=true
                        string_char="$char"
                    elif [[ "$string_char" == "$char" && "$prev_char" != "\\" ]]; then
                        in_string=false
                        string_char=""
                    fi
                fi
                
                # Only count braces outside of strings
                if [[ "$in_string" == false ]]; then
                    if [[ "$char" == "{" ]]; then
                        ((brace_count++))
                    elif [[ "$char" == "}" ]]; then
                        ((brace_count--))
                    fi
                fi
                
                ((i++))
            done
            
            # If brace count returns to 0 and we're not in a string, we've found the end
            if [[ $brace_count -eq 0 ]] && [[ "$in_string" == false ]] && [[ "$line" =~ \} ]]; then
                in_function=false
                in_string=false
                string_char=""
                continue
            fi
        else
            # Write non-function lines to temp file with error checking
            if ! echo "$line" >> "$temp_file" 2>&1; then
                write_failed=true
                break
            fi
        fi
    done < "$FUNCTIONS_FILE"
    
    # Check if write failed during processing
    if [[ "$write_failed" == true ]]; then
        release_functions_lock
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        # Provide specific error messages
        if [[ ! -w "$(dirname "$temp_file")" ]] 2>/dev/null && [[ -d "$(dirname "$temp_file")" ]]; then
            echo -e "${RED}Error:${NC} Permission denied - cannot write to temporary directory: $(dirname "$temp_file")"
        elif [[ -f "$temp_file" ]] && [[ ! -w "$temp_file" ]] 2>/dev/null; then
            echo -e "${RED}Error:${NC} Permission denied - cannot write to temporary file: $temp_file"
        else
            echo -e "${RED}Error:${NC} Failed to write to temporary file during function removal"
            echo "  This may be due to: disk full, permission issues, or filesystem errors"
        fi
        return 1
    fi
    
    # Replace original file
    if mv "$temp_file" "$FUNCTIONS_FILE"; then
        # Unregister temp file since it was successfully moved
        unregister_temp_file "$temp_file"
        release_functions_lock
        echo -e "${GREEN}✓${NC} Function '$name' removed"
        echo "Backup saved to: ${FUNCTIONS_FILE}.bak"
    else
        # Restore from backup if mv failed
        if [[ -f "${FUNCTIONS_FILE}.bak" ]]; then
            mv "${FUNCTIONS_FILE}.bak" "$FUNCTIONS_FILE" 2>/dev/null
            echo -e "${YELLOW}Warning:${NC} Failed to update functions file - restored from backup"
        fi
        release_functions_lock
        unregister_temp_file "$temp_file"
        rm -f "$temp_file"
        echo -e "${RED}Error:${NC} Failed to update functions file"
        return 1
    fi
}

# Audit command
function am_audit() {
    if [[ "$1" == "--help" || "$1" == "-h" ]]; then
        am_audit_help
        return 0
    fi
    
    # Reset counters
    am_errors=0
    am_warnings=0
    am_info=0
    
    echo -e "${CYAN}=== Alias Manager Audit Report ===${NC}"
    echo
    
    # Check for duplicates
    echo -e "${YELLOW}Checking for duplicates...${NC}"
    check_duplicates
    
    # Check for naming conflicts with system commands
    echo -e "${YELLOW}Checking for system command conflicts...${NC}"
    check_system_conflicts
    
    # Check syntax
    echo -e "${YELLOW}Checking syntax...${NC}"
    check_syntax
    
    # Check file permissions
    echo -e "${YELLOW}Checking file permissions...${NC}"
    check_permissions
    
    # Check for large aliases
    echo -e "${YELLOW}Checking for complex aliases...${NC}"
    check_complex_aliases
    
    # Check for invalid names
    echo -e "${YELLOW}Checking for invalid names...${NC}"
    check_invalid_names
    
    # Summary
    echo
    echo -e "${CYAN}=== Summary ===${NC}"
    echo "Errors: $am_errors, Warnings: $am_warnings, Info: $am_info"
    
    if [[ $am_errors -gt 0 ]]; then
        return 1
    fi
}

# Audit: Check for duplicates
function check_duplicates() {
    # Get system aliases from common configuration files
    local system_config_files=()
    if [[ -f "$HOME/.bashrc" ]]; then
        system_config_files+=("$HOME/.bashrc")
    fi
    if [[ -f "$HOME/.zshrc" ]]; then
        system_config_files+=("$HOME/.zshrc")
    fi
    if [[ -f "$HOME/.bash_aliases" ]]; then
        system_config_files+=("$HOME/.bash_aliases")
    fi
    if [[ -f "$HOME/.zsh_aliases" ]]; then
        system_config_files+=("$HOME/.zsh_aliases")
    fi
    if [[ -f "$HOME/.bash_profile" ]]; then
        system_config_files+=("$HOME/.bash_profile")
    fi
    if [[ -f "$HOME/.profile" ]]; then
        system_config_files+=("$HOME/.profile")
    fi
    
    # Extract system aliases from config files
    local system_aliases=""
    for config_file in "${system_config_files[@]}"; do
        if [[ -f "$config_file" ]] && [[ -r "$config_file" ]]; then
            # Extract alias names, excluding our files
            local file_aliases=$(grep -E "^[[:space:]]*alias[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*=" "$config_file" 2>/dev/null | \
                sed 's/^[[:space:]]*alias[[:space:]]*//' | cut -d'=' -f1)
            if [[ -n "$file_aliases" ]]; then
                system_aliases="${system_aliases}${file_aliases}"$'\n'
            fi
        fi
    done
    system_aliases=$(echo "$system_aliases" | sort | uniq)
    
    # Also check currently loaded aliases (in case files are sourced)
    local loaded_aliases=""
    if command -v alias >/dev/null 2>&1; then
        loaded_aliases=$(alias 2>/dev/null | sed 's/^alias //' | cut -d'=' -f1 | sort | uniq)
    fi
    
    # Get alias-manager aliases
    local alias_names=""
    if [[ -f "$ALIASES_FILE" ]]; then
        alias_names=$(grep "^alias " "$ALIASES_FILE" 2>/dev/null | sed 's/^alias //' | cut -d'=' -f1 | sort)
    fi
    
    # Get alias-manager functions
    local function_names=""
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        function_names=$(grep -E "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)" "$FUNCTIONS_FILE" 2>/dev/null | \
            sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(\).*/\1/' | sort | uniq)
    fi
    
    # Check for duplicates between alias-manager aliases and functions
    if [[ -n "$alias_names" ]] && [[ -n "$function_names" ]]; then
        while IFS= read -r name; do
            if [[ -n "$name" ]] && echo "$function_names" | grep -q "^$name$"; then
                echo -e "  ${YELLOW}[WARNING]${NC} Duplicate name '$name' found in both aliases and functions"
                ((am_warnings++))
            fi
        done <<< "$alias_names"
    fi
    
    # Check alias-manager aliases against system aliases from config files
    if [[ -n "$alias_names" ]] && [[ -n "$system_aliases" ]]; then
        while IFS= read -r name; do
            if [[ -z "$name" ]]; then
                continue
            fi
            
            # Check if name exists in system config files
            if echo "$system_aliases" | grep -q "^$name$"; then
                # Find which file defines it
                local defining_file=""
                for config_file in "${system_config_files[@]}"; do
                    if [[ -f "$config_file" ]] && grep -qE "^[[:space:]]*alias[[:space:]]+${name}=" "$config_file" 2>/dev/null; then
                        defining_file="$config_file"
                        break
                    fi
                done
                
                # Get system alias definition
                local system_def=""
                if [[ -n "$defining_file" ]]; then
                    system_def=$(grep -E "^[[:space:]]*alias[[:space:]]+${name}=" "$defining_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*alias[[:space:]]*//')
                fi
                
                # Get our alias definition
                local our_def=""
                if [[ -f "$ALIASES_FILE" ]]; then
                    our_def=$(grep "^alias $name=" "$ALIASES_FILE" 2>/dev/null | head -1 | sed 's/^alias //')
                fi
                
                if [[ -n "$system_def" ]] && [[ -n "$our_def" ]]; then
                    # Compare definitions
                    if [[ "$system_def" != "$our_def" ]]; then
                        echo -e "  ${RED}[ERROR]${NC} Alias '$name' conflicts with system alias in $defining_file"
                        echo -e "    System: $system_def"
                        echo -e "    Ours:   $our_def"
                        ((am_errors++))
                    else
                        echo -e "  ${BLUE}[INFO]${NC} Alias '$name' matches system alias in $defining_file"
                        ((am_info++))
                    fi
                elif [[ -n "$system_def" ]]; then
                    echo -e "  ${RED}[ERROR]${NC} Alias '$name' conflicts with system alias in $defining_file: $system_def"
                    ((am_errors++))
                fi
            fi
        done <<< "$alias_names"
    fi
    
    # Check alias-manager aliases against currently loaded aliases (if different from our file)
    if [[ -n "$alias_names" ]] && [[ -n "$loaded_aliases" ]]; then
        while IFS= read -r name; do
            if [[ -z "$name" ]]; then
                continue
            fi
            
            # Check if name exists as a loaded alias
            if echo "$loaded_aliases" | grep -q "^$name$"; then
                # Check if it's defined in our file
                local in_our_file=false
                if [[ -f "$ALIASES_FILE" ]] && grep -q "^alias $name=" "$ALIASES_FILE" 2>/dev/null; then
                    in_our_file=true
                fi
                
                # Get definitions
                local loaded_def=$(alias "$name" 2>/dev/null | sed 's/^alias //')
                local our_def=""
                if [[ "$in_our_file" == true ]] && [[ -f "$ALIASES_FILE" ]]; then
                    our_def=$(grep "^alias $name=" "$ALIASES_FILE" 2>/dev/null | head -1 | sed 's/^alias //')
                fi
                
                # If definitions don't match, it's a conflict
                if [[ "$in_our_file" == true ]] && [[ -n "$our_def" ]] && [[ -n "$loaded_def" ]] && [[ "$our_def" != "$loaded_def" ]]; then
                    echo -e "  ${RED}[ERROR]${NC} Alias '$name' conflicts with loaded alias"
                    echo -e "    Loaded: $loaded_def"
                    echo -e "    Ours:   $our_def"
                    ((am_errors++))
                elif [[ "$in_our_file" == false ]] && [[ -n "$loaded_def" ]]; then
                    echo -e "  ${RED}[ERROR]${NC} Alias '$name' conflicts with loaded system alias: $loaded_def"
                    ((am_errors++))
                fi
            fi
            
            # Also check if it's a function
            local type_output=$(type -t "$name" 2>/dev/null)
            if [[ "$type_output" == "function" ]]; then
                echo -e "  ${RED}[ERROR]${NC} Alias '$name' conflicts with existing function"
                ((am_errors++))
            fi
        done <<< "$alias_names"
    fi
    
    # Extract system functions from config files
    local system_functions=""
    for config_file in "${system_config_files[@]}"; do
        if [[ -f "$config_file" ]] && [[ -r "$config_file" ]]; then
            # Extract function names
            local file_functions=$(grep -E "^[[:space:]]*function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(|^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(\)" "$config_file" 2>/dev/null | \
                sed -E 's/^[[:space:]]*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/; s/^[[:space:]]*([a-zA-Z_][a-zA-Z0-9_]*)\(.*/\1/')
            if [[ -n "$file_functions" ]]; then
                system_functions="${system_functions}${file_functions}"$'\n'
            fi
        fi
    done
    system_functions=$(echo "$system_functions" | sort | uniq)
    
    # Check alias-manager functions against system aliases and functions
    if [[ -n "$function_names" ]]; then
        while IFS= read -r name; do
            if [[ -z "$name" ]]; then
                continue
            fi
            
            # Check against system aliases from config files
            if echo "$system_aliases" | grep -q "^$name$"; then
                local defining_file=""
                for config_file in "${system_config_files[@]}"; do
                    if [[ -f "$config_file" ]] && grep -qE "^[[:space:]]*alias[[:space:]]+${name}=" "$config_file" 2>/dev/null; then
                        defining_file="$config_file"
                        break
                    fi
                done
                if [[ -n "$defining_file" ]]; then
                    local alias_def=$(grep -E "^[[:space:]]*alias[[:space:]]+${name}=" "$defining_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*alias[[:space:]]*//')
                    echo -e "  ${RED}[ERROR]${NC} Function '$name' conflicts with system alias in $defining_file: $alias_def"
                    ((am_errors++))
                fi
            fi
            
            # Check against system functions from config files
            if echo "$system_functions" | grep -q "^$name$"; then
                local defining_file=""
                for config_file in "${system_config_files[@]}"; do
                    if [[ -f "$config_file" ]] && grep -qE "^[[:space:]]*function[[:space:]]+${name}[[:space:]]*\(|^[[:space:]]*${name}[[:space:]]*\(\)" "$config_file" 2>/dev/null; then
                        defining_file="$config_file"
                        break
                    fi
                done
                if [[ -n "$defining_file" ]]; then
                    echo -e "  ${RED}[ERROR]${NC} Function '$name' conflicts with system function in $defining_file"
                    ((am_errors++))
                fi
            fi
            
            # Check against currently loaded aliases/functions
            local type_output=$(type -t "$name" 2>/dev/null)
            if [[ "$type_output" == "alias" ]]; then
                local alias_def=$(alias "$name" 2>/dev/null | sed 's/^alias //')
                echo -e "  ${RED}[ERROR]${NC} Function '$name' conflicts with loaded alias: $alias_def"
                ((am_errors++))
            elif [[ "$type_output" == "function" ]]; then
                # Check if this function is defined in our file
                local in_our_file=false
                if [[ -f "$FUNCTIONS_FILE" ]] && grep -qE "^[[:space:]]*function[[:space:]]+${name}[[:space:]]*\(|^[[:space:]]*${name}[[:space:]]*\()" "$FUNCTIONS_FILE" 2>/dev/null; then
                    in_our_file=true
                fi
                
                # If it's a system function (not from our file), it's a conflict
                if [[ "$in_our_file" == false ]]; then
                    echo -e "  ${RED}[ERROR]${NC} Function '$name' conflicts with loaded system function"
                    ((am_errors++))
                fi
            fi
        done <<< "$function_names"
    fi
}

# Audit: Check system conflicts
function check_system_conflicts() {
    if [[ -f "$ALIASES_FILE" ]]; then
        local alias_names=$(grep "^alias " "$ALIASES_FILE" 2>/dev/null | sed 's/^alias //' | cut -d'=' -f1)
        
        while IFS= read -r name; do
            if [[ -n "$name" ]] && command -v "$name" >/dev/null 2>&1; then
                # Check if it's a system command (not our alias)
                local type_output=$(type -t "$name" 2>/dev/null)
                if [[ "$type_output" != "alias" ]]; then
                    echo -e "  ${BLUE}[INFO]${NC} Alias '$name' shadows system command"
                    ((am_info++))
                fi
            fi
        done <<< "$alias_names"
    fi
}

# Audit: Check syntax
function check_syntax() {
    # Check aliases file
    if [[ -f "$ALIASES_FILE" ]]; then
        if ! bash -n "$ALIASES_FILE" 2>/dev/null; then
            echo -e "  ${RED}[ERROR]${NC} Syntax error in aliases file"
            ((am_errors++))
        fi
    fi
    
    # Check functions file
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        if ! bash -n "$FUNCTIONS_FILE" 2>/dev/null; then
            echo -e "  ${RED}[ERROR]${NC} Syntax error in functions file"
            ((am_errors++))
        fi
    fi
}

# Audit: Check permissions
function check_permissions() {
    for file in "$ALIASES_FILE" "$FUNCTIONS_FILE"; do
        if [[ -e "$file" ]]; then
            if [[ ! -r "$file" ]]; then
                echo -e "  ${RED}[ERROR]${NC} Cannot read $file"
                ((am_errors++))
            fi
            if [[ ! -w "$file" ]]; then
                echo -e "  ${YELLOW}[WARNING]${NC} Cannot write to $file"
                ((am_warnings++))
            fi
        fi
    done
}

# Audit: Check for complex aliases
function check_complex_aliases() {
    if [[ -f "$ALIASES_FILE" ]]; then
        while IFS='=' read -r name cmd; do
            name=$(echo "$name" | sed 's/^alias //' | tr -d ' ')
            if [[ -n "$name" ]] && [[ ${#cmd} -gt 100 ]]; then
                echo -e "  ${BLUE}[INFO]${NC} Alias '$name' is complex (${#cmd} chars) - consider making it a function"
                ((am_info++))
            fi
        done < <(grep "^alias " "$ALIASES_FILE" 2>/dev/null)
    fi
}

# Audit: Check for invalid names
function check_invalid_names() {
    # Check aliases
    if [[ -f "$ALIASES_FILE" ]]; then
        while IFS='=' read -r name rest; do
            name=$(echo "$name" | sed 's/^alias //' | tr -d ' ')
            if [[ -n "$name" ]] && ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo -e "  ${RED}[ERROR]${NC} Invalid alias name: '$name'"
                ((am_errors++))
            fi
        done < <(grep "^alias " "$ALIASES_FILE" 2>/dev/null)
    fi
    
    # Check functions
    if [[ -f "$FUNCTIONS_FILE" ]]; then
        local function_names=$(grep -E "^[[:space:]]*function[[:space:]]+[^[:space:]]+|^[[:space:]]*[^[:space:]]+\(\)" "$FUNCTIONS_FILE" 2>/dev/null | \
            sed -E 's/^[[:space:]]*function[[:space:]]+([^[:space:](]+).*/\1/; s/^[[:space:]]*([^[:space:](]+)\(\).*/\1/')
        
        while IFS= read -r name; do
            if [[ -n "$name" ]] && ! [[ "$name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
                echo -e "  ${RED}[ERROR]${NC} Invalid function name: '$name'"
                ((am_errors++))
            fi
        done <<< "$function_names"
    fi
}

# File locking functions
# Global variables to track lock file descriptors
_aliases_lock_fd=0
_functions_lock_fd=0

# Acquire lock for aliases file
function acquire_aliases_lock() {
    local lock_file="${ALIASES_FILE}.lock"
    local timeout=${1:-10}  # Default 10 second timeout
    
    # Create directory for lock file
    mkdir -p "$(dirname "$lock_file")"
    
    # Try to acquire exclusive lock with timeout
    if command -v flock >/dev/null 2>&1; then
        # Use a fixed file descriptor (200 for aliases, 201 for functions)
        # Open in append mode to avoid "cannot overwrite" errors
        if ! exec 200>>"$lock_file" 2>/dev/null; then
            echo -e "${RED}Error:${NC} Cannot open lock file: $lock_file"
            return 1
        fi
        
        if ! flock -w "$timeout" 200; then
            exec 200>&-
            echo -e "${RED}Error:${NC} Cannot acquire lock for aliases file (timeout after ${timeout}s)"
            return 1
        fi
        
        _aliases_lock_fd=200
    else
        # Fallback: use simple file-based locking (less reliable but better than nothing)
        local lock_attempts=0
        while ! (set -C; echo $$ > "$lock_file" 2>/dev/null); do
            sleep 0.1
            ((lock_attempts++))
            if [[ $lock_attempts -gt $((timeout * 10)) ]]; then
                echo -e "${RED}Error:${NC} Cannot acquire lock for aliases file (timeout after ${timeout}s)"
                return 1
            fi
            # Check if lock file is stale (process no longer exists)
            if [[ -f "$lock_file" ]]; then
                local lock_pid=$(cat "$lock_file" 2>/dev/null)
                if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                    rm -f "$lock_file"
                fi
            fi
        done
        _aliases_lock_fd=200  # Set to indicate lock is held
    fi
    
    return 0
}

# Release lock for aliases file
function release_aliases_lock() {
    if [[ $_aliases_lock_fd -eq 200 ]]; then
        if command -v flock >/dev/null 2>&1; then
            exec 200>&-
        else
            # Clean up lock file for fallback method
            if [[ -f "${ALIASES_FILE}.lock" ]]; then
                local lock_pid=$(cat "${ALIASES_FILE}.lock" 2>/dev/null)
                if [[ "$lock_pid" == "$$" ]]; then
                    rm -f "${ALIASES_FILE}.lock"
                fi
            fi
        fi
        _aliases_lock_fd=0
    fi
}

# Acquire lock for functions file
function acquire_functions_lock() {
    local lock_file="${FUNCTIONS_FILE}.lock"
    local timeout=${1:-10}  # Default 10 second timeout
    
    # Create directory for lock file
    mkdir -p "$(dirname "$lock_file")"
    
    # Try to acquire exclusive lock with timeout
    if command -v flock >/dev/null 2>&1; then
        # Use a fixed file descriptor (201 for functions)
        # Open in append mode to avoid "cannot overwrite" errors
        if ! exec 201>>"$lock_file" 2>/dev/null; then
            echo -e "${RED}Error:${NC} Cannot open lock file: $lock_file"
            return 1
        fi
        
        if ! flock -w "$timeout" 201; then
            exec 201>&-
            echo -e "${RED}Error:${NC} Cannot acquire lock for functions file (timeout after ${timeout}s)"
            return 1
        fi
        
        _functions_lock_fd=201
    else
        # Fallback: use simple file-based locking (less reliable but better than nothing)
        local lock_attempts=0
        while ! (set -C; echo $$ > "$lock_file" 2>/dev/null); do
            sleep 0.1
            ((lock_attempts++))
            if [[ $lock_attempts -gt $((timeout * 10)) ]]; then
                echo -e "${RED}Error:${NC} Cannot acquire lock for functions file (timeout after ${timeout}s)"
                return 1
            fi
            # Check if lock file is stale (process no longer exists)
            if [[ -f "$lock_file" ]]; then
                local lock_pid=$(cat "$lock_file" 2>/dev/null)
                if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                    rm -f "$lock_file"
                fi
            fi
        done
        _functions_lock_fd=201  # Set to indicate lock is held
    fi
    
    return 0
}

# Release lock for functions file
function release_functions_lock() {
    if [[ $_functions_lock_fd -eq 201 ]]; then
        if command -v flock >/dev/null 2>&1; then
            exec 201>&-
        else
            # Clean up lock file for fallback method
            if [[ -f "${FUNCTIONS_FILE}.lock" ]]; then
                local lock_pid=$(cat "${FUNCTIONS_FILE}.lock" 2>/dev/null)
                if [[ "$lock_pid" == "$$" ]]; then
                    rm -f "${FUNCTIONS_FILE}.lock"
                fi
            fi
        fi
        _functions_lock_fd=0
    fi
}

# Temporary file management functions
# Register a temporary file for automatic cleanup
function register_temp_file() {
    local temp_file="$1"
    if [[ -n "$temp_file" ]] && [[ -f "$temp_file" ]]; then
        am_temp_files+=("$temp_file")
    fi
}

# Unregister a temporary file (when it's been successfully moved or deleted)
function unregister_temp_file() {
    local temp_file="$1"
    if [[ -n "$temp_file" ]]; then
        local new_array=()
        for file in "${am_temp_files[@]}"; do
            if [[ "$file" != "$temp_file" ]]; then
                new_array+=("$file")
            fi
        done
        am_temp_files=("${new_array[@]}")
    fi
}

# Cleanup all registered temporary files
function cleanup_temp_files() {
    for temp_file in "${am_temp_files[@]}"; do
        if [[ -f "$temp_file" ]]; then
            rm -f "$temp_file" 2>/dev/null
        fi
    done
    am_temp_files=()
}

# Cleanup function to release all locks and temp files on exit
function cleanup_locks() {
    release_aliases_lock
    release_functions_lock
    cleanup_temp_files
}

# Set trap to cleanup locks and temp files on exit, errors, and signals
trap cleanup_locks EXIT
trap cleanup_locks ERR
trap cleanup_locks INT TERM

# Helper function to create backup with rotation
function create_backup_with_rotation() {
    local source_file="$1"
    local backup_file="${source_file}.bak"
    
    # If backup exists, rotate it
    if [[ -f "$backup_file" ]]; then
        local rotated_backup="${backup_file}.old"
        # Remove oldest backup if it exists
        if [[ -f "$rotated_backup" ]]; then
            rm -f "$rotated_backup"
        fi
        # Rotate current backup
        mv "$backup_file" "$rotated_backup" 2>/dev/null
    fi
    
    # Create new backup
    if cp "$source_file" "$backup_file" 2>&1; then
        return 0
    else
        return 1
    fi
}

# Helper function to check available disk space
function check_disk_space() {
    local target_dir="$1"
    local min_space_kb=${2:-1024}  # Default 1MB minimum
    
    # Get directory path (use parent if file path provided)
    if [[ -f "$target_dir" ]]; then
        target_dir="$(dirname "$target_dir")"
    fi
    
    # Ensure directory exists
    if [[ ! -d "$target_dir" ]]; then
        target_dir="$(dirname "$target_dir")"
    fi
    
    # Check available space (cross-platform)
    local available_kb=0
    if command -v df >/dev/null 2>&1; then
        # Try POSIX df first (works on most systems)
        if available_kb=$(df -P "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}'); then
            if [[ -n "$available_kb" ]] && [[ "$available_kb" =~ ^[0-9]+$ ]]; then
                if [[ $available_kb -lt $min_space_kb ]]; then
                    echo -e "${RED}Error:${NC} Insufficient disk space"
                    echo "  Available: ${available_kb}KB, Required: ${min_space_kb}KB"
                    echo "  Directory: $target_dir"
                    return 1
                fi
                return 0
            fi
        fi
        
        # Fallback for macOS/BSD df (blocks instead of KB)
        if available_kb=$(df -k "$target_dir" 2>/dev/null | awk 'NR==2 {print $4}'); then
            if [[ -n "$available_kb" ]] && [[ "$available_kb" =~ ^[0-9]+$ ]]; then
                if [[ $available_kb -lt $min_space_kb ]]; then
                    echo -e "${RED}Error:${NC} Insufficient disk space"
                    echo "  Available: ${available_kb}KB, Required: ${min_space_kb}KB"
                    echo "  Directory: $target_dir"
                    return 1
                fi
                return 0
            fi
        fi
    fi
    
    # If we can't check, warn but don't fail (better than blocking)
    echo -e "${YELLOW}Warning:${NC} Cannot verify disk space availability"
    return 0
}

# Helper function to escape special regex characters in names
function escape_regex_special() {
    local name="$1"
    # Escape special regex characters: . [ ] { } ( ) * + ? ^ $ | \
    echo "$name" | sed 's/\./\\./g; s/\[/\\[/g; s/\]/\\]/g; s/{/\\{/g; s/}/\\}/g; s/(/\\(/g; s/)/\\)/g; s/\*/\\*/g; s/+/\\+/g; s/?/\\?/g; s/\^/\\^/g; s/\$/\\$/g; s/|/\\|/g; s/\\/\\\\/g'
}

# Helper functions
function check_alias_exists() {
    local name="$1"
    local escaped_name=$(escape_regex_special "$name")
    if [[ -f "$ALIASES_FILE" ]] && grep -q "^alias $escaped_name=" "$ALIASES_FILE" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

function check_function_exists() {
    local name="$1"
    local escaped_name=$(escape_regex_special "$name")
    if [[ -f "$FUNCTIONS_FILE" ]] && grep -qE "^[[:space:]]*(function[[:space:]]+${escaped_name}[[:space:]]*\(|${escaped_name}[[:space:]]*\()" "$FUNCTIONS_FILE" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

function get_alias_definition() {
    local name="$1"
    local escaped_name=$(escape_regex_special "$name")
    grep "^alias $escaped_name=" "$ALIASES_FILE" 2>/dev/null | sed 's/^alias [^=]*=//'
}

function get_function_summary() {
    local name="$1"
    echo "function $name() { ... }"
}

# Cross-platform read function
function read_with_prompt() {
    local prompt="$1"
    shift
    local var_name="${!#}"  # Last argument is the variable name
    
    # Remove variable name from arguments
    set -- "${@:1:$(($#-1))}"
    
    if [[ -t 0 ]]; then
        # Interactive terminal
        read -p "$prompt" "$@" "$var_name" < /dev/tty
    else
        # Non-interactive or piped input
        echo -n "$prompt"
        read "$@" "$var_name"
    fi
}

# Help functions for subcommands
function am_add_help() {
    cat << EOF
${CYAN}am add${NC} - Add a new alias or function

${YELLOW}Usage:${NC}
  am add [options] {name} [command]
  am add function {name} [command]

${YELLOW}Options:${NC}
  -a, --alias      Add as alias
  -f, --function   Add as function
  --force          Remove existing alias/function with same name before adding
  --dry-run        Preview changes without actually modifying files
  -h, --help       Show this help message

${YELLOW}Arguments:${NC}
  {name}           Name for the alias or function (alphanumeric + underscore)
  command          Command to execute (optional for functions)

${YELLOW}Notes:${NC}
  - If type is not specified, you'll be prompted to choose
  - For functions without a command, an editor will open
  - Names must start with a letter or underscore
  - --force will automatically remove existing alias/function before adding

${YELLOW}Examples:${NC}
  am add ll 'ls -la'              # Prompts for type
  am add -a gs 'git status'       # Add as alias
  am add -f greet                 # Opens editor for function
  am add function deploy          # Opens editor for function
EOF
}

function am_list_help() {
    cat << EOF
${CYAN}am list${NC} - List aliases and functions

${YELLOW}Usage:${NC}
  am list [options] [{name}]

${YELLOW}Options:${NC}
  -a, --aliases    Show only aliases
  -f, --functions  Show only functions
  -c, --commands   Show commands alongside alias names
  -h, --help       Show this help message

${YELLOW}Arguments:${NC}
  {name}           Show definition of specific alias or function

${YELLOW}Examples:${NC}
  am list                  # List all aliases and functions
  am list -a               # List only aliases
  am list -a -c            # List aliases with their commands
  am list ll               # Show definition of 'll' (alias or function)
EOF
}

function am_remove_help() {
    cat << EOF
${CYAN}am rm${NC} - Remove an alias or function

${YELLOW}Usage:${NC}
  am rm [options] {name}

${YELLOW}Options:${NC}
  -a, --alias      Remove only the alias
  -f, --function   Remove only the function
  --force          Skip confirmation prompt
  --dry-run        Preview changes without actually removing
  -h, --help       Show this help message

${YELLOW}Arguments:${NC}
  {name}           Name of alias or function to remove

${YELLOW}Notes:${NC}
  - If name exists as both alias and function, you'll be prompted
  - Backups are created before removal
  - --dry-run shows what would be removed without making changes

${YELLOW}Examples:${NC}
  am rm ll                 # Remove 'll' (prompts if duplicate)
  am rm -a gs              # Remove only the alias 'gs'
  am rm --force deploy     # Remove without confirmation
EOF
}

function am_audit_help() {
    cat << EOF
${CYAN}am audit${NC} - Audit aliases and functions for issues

${YELLOW}Usage:${NC}
  am audit [options]

${YELLOW}Options:${NC}
  -h, --help       Show this help message

${YELLOW}Checks performed:${NC}
  - Duplicate names in aliases and functions
  - Naming conflicts with system commands
  - Syntax errors in definition files
  - File permission issues
  - Complex aliases that should be functions
  - Invalid characters in names

${YELLOW}Output:${NC}
  [ERROR]   - Critical issues that need fixing
  [WARNING] - Potential problems to review
  [INFO]    - Suggestions for improvement

${YELLOW}Example:${NC}
  am audit         # Run full audit
EOF
}

function am_path_help() {
    cat << EOF
${CYAN}am path${NC} / ${CYAN}am show${NC} - Show file paths and optionally open them

${YELLOW}Usage:${NC}
  am path [options]
  am show [options]

${YELLOW}Options:${NC}
  -o, --open       Open the file(s) in your default editor
  -a, --aliases    Show only aliases file path
  -f, --functions  Show only functions file path
  -h, --help       Show this help message

${YELLOW}Description:${NC}
  Displays the file paths where aliases and functions are stored.
  Use -o/--open to open the file(s) in your editor (\$EDITOR).

${YELLOW}Examples:${NC}
  am path                    # Show both file paths
  am path --open             # Show paths and open both files
  am path -a --open          # Show and open only aliases file
  am show -f                 # Show only functions file path
EOF
}

function am_install_help() {
    cat << EOF
${CYAN}am install${NC} - Setup auto-sourcing in shell config files

${YELLOW}Usage:${NC}
  am install [options]

${YELLOW}Options:${NC}
  --force, -f        Force reinstallation (removes existing installation)
  --shell <type>     Specify shell type (bash, zsh). Auto-detected if not specified
  -h, --help         Show this help message

${YELLOW}Description:${NC}
  Adds sourcing commands to your shell configuration file (.bashrc, .zshrc, etc.)
  so that aliases and functions are automatically loaded in new shell sessions.

${YELLOW}Examples:${NC}
  am install                    # Install for current shell (auto-detected)
  am install --shell bash       # Install for bash specifically
  am install --force            # Reinstall (removes old installation first)
EOF
}

function am_status_help() {
    cat << EOF
${CYAN}am status${NC} - Check installation and sourcing status

${YELLOW}Usage:${NC}
  am status

${YELLOW}Description:${NC}
  Shows the current status of Alias Manager including:
  - File locations and existence
  - Installation status in shell config files
  - Whether files are sourced in current session
  - Statistics (count of aliases and functions)

${YELLOW}Example:${NC}
  am status                     # Show full status
EOF
}

function am_search_help() {
    cat << EOF
${CYAN}am search${NC} - Search aliases and functions by name or command

${YELLOW}Usage:${NC}
  am search <pattern> [options]

${YELLOW}Options:${NC}
  -a, --aliases      Search only aliases
  -f, --functions    Search only functions
  -c, --commands     Search in command definitions (not just names)
  -h, --help         Show this help message

${YELLOW}Description:${NC}
  Searches for aliases and functions matching the given pattern.
  By default searches both names and definitions. Use --commands to search
  within command definitions.

${YELLOW}Examples:${NC}
  am search ls                  # Find aliases/functions with 'ls' in name or command
  am search git -a              # Search only aliases for 'git'
  am search deploy --commands   # Search command definitions for 'deploy'
EOF
}

function am_edit_help() {
    cat << EOF
${CYAN}am edit${NC} - Edit an existing alias or function

${YELLOW}Usage:${NC}
  am edit <name>

${YELLOW}Description:${NC}
  Opens the specified alias or function in your default editor (\$EDITOR).
  For aliases, opens a temporary file with the current definition.
  For functions, opens the functions file for manual editing.

${YELLOW}Examples:${NC}
  am edit ll                    # Edit alias 'll'
  am edit myfunc                # Edit function 'myfunc'
EOF
}

function am_update_help() {
    cat << EOF
${CYAN}am update${NC} - Update an existing alias or function

${YELLOW}Usage:${NC}
  am update <name> <command>

${YELLOW}Description:${NC}
  Updates an existing alias or function with a new command.
  Automatically detects whether the name is an alias or function.

${YELLOW}Examples:${NC}
  am update ll 'ls -lah'        # Update alias 'll'
  am update greet 'echo Hello'  # Update function 'greet'
EOF
}

# Export the main function for use
export -f am

# If script is executed directly (not sourced), run the command
# Detection logic:
# - If BASH_SOURCE[0] == $0, it's direct execution (./am.sh)
# - If BASH_SOURCE array length is 1 and contains am.sh, it's direct execution (bash am.sh)
# - When sourced, BASH_SOURCE has the script but $0 is the parent shell
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Direct execution: ./am.sh
    am "$@"
    exit $?
elif [[ "${#BASH_SOURCE[@]}" -eq 1 ]] && [[ "${BASH_SOURCE[0]}" == *"am.sh"* ]]; then
    # Direct execution: bash am.sh
    am "$@"
    exit $?
fi