#!/bin/bash

# Script to copy individual TV episodes or movies in synced-media directory
# Usage: ./sync_media.sh [--tv|--movie] "Show/Movie Name" [episode_pattern]

TV_SOURCE_DIR="/mnt/user/data/media/tv"
MOVIE_SOURCE_DIR="/mnt/user/data/media/movies"
SYNC_DIR="/mnt/user/data/others/synced-media"

# Create the sync directories if they don't exist
mkdir -p "$SYNC_DIR/tv"
mkdir -p "$SYNC_DIR/movies"

# Function to show usage
show_usage() {
    echo "Usage: $0 [--tv|--movie] \"Show/Movie Name\" [episode_pattern]"
    echo ""
    echo "Options:"
    echo "  --tv        Search only TV shows"
    echo "  --movie     Search only movies"
    echo "  --execute   Actually copy (default is dry run)"
    echo "  --help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --tv \"Bear\"                    # Dry run: show what would be synced"
    echo "  $0 --tv \"Bear\" --execute           # Actually copy"
    echo "  $0 --movie \"Inception\"             # Dry run: find Inception movie"
    echo "  $0 --tv \"Severance\" \"S01E01\"       # Show episodes matching S01E01"
    echo "  $0 \"Bear\"                         # Auto-detect (TV show or movie)"
    echo ""
    echo "Available TV shows:"
    ls -1 "$TV_SOURCE_DIR" 2>/dev/null | head -5
    echo ""
    echo "Available movies:"
    ls -1 "$MOVIE_SOURCE_DIR" 2>/dev/null | head -5
    echo "  ... (showing first 5 of each)"
}

# Parse command line arguments
MEDIA_TYPE=""
MEDIA_PATTERN=""
EPISODE_PATTERN=""
DRY_RUN=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --tv)
            MEDIA_TYPE="tv"
            shift
            ;;
        --movie|--movies)
            MEDIA_TYPE="movie"
            shift
            ;;
        --execute)
            DRY_RUN=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            if [ -z "$MEDIA_PATTERN" ]; then
                MEDIA_PATTERN="$1"
            else
                EPISODE_PATTERN="$1"
            fi
            shift
            ;;
    esac
done

# Function to find media based on type
find_media() {
    local media_pattern="$1"
    local episode_pattern="$2"
    local force_type="$3"
    
    if [ -z "$media_pattern" ]; then
        show_usage
        exit 1
    fi
    
    # Search based on specified type or auto-detect
    case $force_type in
        "tv")
            find_tv_shows "$media_pattern" "$episode_pattern"
            ;;
        "movie")
            find_movies_by_pattern "$media_pattern"
            ;;
        *)
            # Auto-detect mode
            local tv_matches=()
            while IFS= read -r -d '' dir; do
                tv_matches+=("$dir")
            done < <(find "$TV_SOURCE_DIR" -maxdepth 1 -type d -iname "*${media_pattern}*" -print0 2>/dev/null)
            local movie_matches=()
            while IFS= read -r -d '' file; do
                if [[ "$(basename "$file")" == *"$media_pattern"* ]]; then
                    movie_matches+=("$file")
                fi
            done < <(find "$MOVIE_SOURCE_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -iname "*${media_pattern}*" -print0 2>/dev/null)
            
            local total_matches=$((${#tv_matches[@]} + ${#movie_matches[@]}))
            
            if [ $total_matches -eq 0 ]; then
                echo "❌ No TV shows or movies found matching: $media_pattern"
                echo "💡 Try using --tv or --movie to search specific media types"
                return 1
            fi
            
            # If we have both TV and movie matches, let user choose by number
            if [ ${#tv_matches[@]} -gt 0 ] && [ ${#movie_matches[@]} -gt 0 ]; then
                echo "🎬 Found both TV shows and movies matching '$media_pattern':"
                echo ""
                
                # Create combined array with all matches
                local all_matches=()
                local match_types=()
                local counter=1
                
                echo "TV Shows:"
                for match in "${tv_matches[@]}"; do
                    echo "[$counter]   📺 $(basename "$match")"
                    all_matches+=("$match")
                    match_types+=("tv")
                    ((counter++))
                done
                
                echo "Movies:"
                for match in "${movie_matches[@]}"; do
                    echo "[$counter]   🎬 $(basename "$match")"
                    all_matches+=("$match")
                    match_types+=("movie")
                    ((counter++))
                done
                
                echo ""
                echo "💡 Next time, use --tv or --movie to skip this prompt"
                
                while true; do
                    read -p "Choose by number (1-$((counter-1))) or 'q' to quit: " selection
                    
                    if [[ "$selection" == "q" ]]; then
                        echo "Cancelled."
                        return 0
                    fi
                    
                    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -lt $counter ]; then
                        local idx=$((selection-1))
                        local selected_match="${all_matches[$idx]}"
                        local selected_type="${match_types[$idx]}"
                        
                        if [ "$selected_type" = "tv" ]; then
                            handle_tv_show "$selected_match" "$episode_pattern"
                        else
                            handle_movies "$selected_match"
                        fi
                        return 0
                    else
                        echo "Please enter a number between 1 and $((counter-1))"
                    fi
                done
            elif [ ${#tv_matches[@]} -gt 0 ]; then
                find_tv_shows "$media_pattern" "$episode_pattern"
            else
                handle_movies "${movie_matches[@]}"
            fi
            ;;
    esac
}

# Function to find TV shows
find_tv_shows() {
    local media_pattern="$1"
    local episode_pattern="$2"
    
    local tv_matches=()
    while IFS= read -r -d '' dir; do
        tv_matches+=("$dir")
    done < <(find "$TV_SOURCE_DIR" -maxdepth 1 -type d -iname "*${media_pattern}*" -print0 2>/dev/null)
    
    if [ ${#tv_matches[@]} -eq 0 ]; then
        echo "❌ No TV shows found matching: $media_pattern"
        return 1
    elif [ ${#tv_matches[@]} -gt 1 ]; then
        echo "🤔 Multiple TV shows found for '$media_pattern':"
        local i=1
        for match in "${tv_matches[@]}"; do
            echo "   $i) $(basename "$match")"
            ((i++))
        done
        echo "   Please be more specific or use the exact name"
        return 1
    fi
    
    handle_tv_show "${tv_matches[0]}" "$episode_pattern"
}

# Function to find movies by pattern
find_movies_by_pattern() {
    local media_pattern="$1"
    
    local movie_matches=()
    while IFS= read -r -d '' file; do
        if [[ "$(basename "$file")" == *"$media_pattern"* ]]; then
            movie_matches+=("$file")
        fi
    done < <(find "$MOVIE_SOURCE_DIR" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -iname "*${media_pattern}*" -print0 2>/dev/null)
    
    if [ ${#movie_matches[@]} -eq 0 ]; then
        echo "❌ No movies found matching: $media_pattern"
        return 1
    fi
    
    handle_movies "${movie_matches[@]}"
}

# Function to handle TV show episodes
handle_tv_show() {
    local show_dir="$1"
    local episode_pattern="$2"
    local show_name=$(basename "$show_dir")
    
    echo "📺 Found TV show: $show_name"
    echo ""
    
    # Find all video files in the show directory
    local episodes=()
    while IFS= read -r -d '' file; do
        episodes+=("$file")
    done < <(find "$show_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.m4v" \) -print0 | sort -z)
    
    if [ ${#episodes[@]} -eq 0 ]; then
        echo "❌ No video files found in: $show_name"
        return 1
    fi
    
    # Filter episodes if pattern provided
    if [ -n "$episode_pattern" ]; then
        local filtered_episodes=()
        for episode in "${episodes[@]}"; do
            if [[ "$(basename "$episode")" =~ $episode_pattern ]]; then
                filtered_episodes+=("$episode")
            fi
        done
        episodes=("${filtered_episodes[@]}")
        
        if [ ${#episodes[@]} -eq 0 ]; then
            echo "❌ No episodes found matching pattern: $episode_pattern"
            return 1
        fi
    fi
    
    # Show available episodes (but skip listing if too many)
    if [ ${#episodes[@]} -le 20 ]; then
        echo "Available episodes (${#episodes[@]} found):"
        for i in "${!episodes[@]}"; do
            local relative_path=$(realpath --relative-to="$show_dir" "${episodes[$i]}")
            printf "%3d) %s\n" $((i+1)) "$relative_path"
        done
        echo ""
    fi
    
    # Interactive selection
    select_and_copy_episodes "$show_dir" "$show_name" "${episodes[@]}"
}

# Function to handle movies
handle_movies() {
    local movies=("$@")
    
    echo "🎬 Found ${#movies[@]} movie(s):"
    for i in "${!movies[@]}"; do
        local movie_name=$(basename "${movies[$i]}")
        printf "%3d) %s\n" $((i+1)) "$movie_name"
    done
    echo ""
    
    # Interactive selection for movies
    while true; do
        read -p "Select movies (e.g., 1,3,5-8 or 'all' or 'q' to quit): " selection
        
        if [[ "$selection" == "q" ]]; then
            echo "Cancelled."
            return 0
        fi
        
        if [[ "$selection" == "all" ]]; then
            copy_movies_with_confirmation "${movies[@]}"
            return 0
        fi
        
        # Parse selection
        local selected_movies=()
        IFS=',' read -ra RANGES <<< "$selection"
        
        for range in "${RANGES[@]}"; do
            if [[ "$range" =~ ^[0-9]+$ ]]; then
                local idx=$((range-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#movies[@]} ]; then
                    selected_movies+=("${movies[$idx]}")
                fi
            elif [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
                local start=$(echo "$range" | cut -d'-' -f1)
                local end=$(echo "$range" | cut -d'-' -f2)
                for ((i=start; i<=end; i++)); do
                    local idx=$((i-1))
                    if [ $idx -ge 0 ] && [ $idx -lt ${#movies[@]} ]; then
                        selected_movies+=("${movies[$idx]}")
                    fi
                done
            fi
        done
        
        if [ ${#selected_movies[@]} -gt 0 ]; then
            copy_movies_with_confirmation "${selected_movies[@]}"
            return 0
        else
            echo "❌ Invalid selection. Try again."
        fi
    done
}

# Function for season-grouped episode selection for shows with many episodes
select_episodes_by_season() {
    local show_dir="$1"
    local show_name="$2"
    shift 2
    local episodes=("$@")
    
    echo ""
    echo "📺 Large TV show detected (${#episodes[@]} episodes)"
    echo "🎯 Using season-grouped selection for better navigation"
    echo ""
    
    # Group episodes by season
    declare -A seasons
    declare -A season_episodes
    
    for i in "${!episodes[@]}"; do
        local episode="${episodes[$i]}"
        local episode_name=$(basename "$episode")
        
        # Extract season number (handles S01, S1, Season 01, Season 1, etc.)
        if [[ "$episode_name" =~ [Ss]([0-9]+) ]]; then
            local season_num=$(printf "%02d" "$((10#${BASH_REMATCH[1]}))")
            seasons["$season_num"]=1
            if [[ -z "${season_episodes[$season_num]}" ]]; then
                season_episodes["$season_num"]="$i"
            else
                season_episodes["$season_num"]="${season_episodes[$season_num]},$i"
            fi
        fi
    done
    
    # Display available seasons
    local season_list=()
    for season in $(printf '%s\n' "${!seasons[@]}" | sort -n); do
        season_list+=("$season")
        local episode_indices=(${season_episodes[$season]//,/ })
        echo "Season $season: ${#episode_indices[@]} episodes"
    done
    
    echo ""
    echo "Selection options:"
    echo "  • Season numbers (e.g., 1,3,4 or 1-3)"
    echo "  • 'latest' - Select the most recent season"
    echo "  • 'all' - Select all episodes"
    echo "  • 'q' - Quit"
    echo ""
    
    while true; do
        read -p "Select seasons: " selection
        
        if [[ "$selection" == "q" ]]; then
            echo "Cancelled."
            return 0
        fi
        
        if [[ "$selection" == "all" ]]; then
            copy_episodes_with_confirmation "$show_dir" "$show_name" "${episodes[@]}"
            return 0
        fi
        
        if [[ "$selection" == "latest" ]]; then
            local latest_season=$(printf '%s\n' "${!seasons[@]}" | sort -n | tail -1)
            local episode_indices=(${season_episodes[$latest_season]//,/ })
            local selected_episodes=()
            for idx in "${episode_indices[@]}"; do
                selected_episodes+=("${episodes[$idx]}")
            done
            
            echo "Selected Season $latest_season (${#selected_episodes[@]} episodes)"
            select_episodes_within_seasons "$show_dir" "$show_name" "${selected_episodes[@]}"
            return $?
        fi
        
        # Parse season selection
        local selected_episodes=()
        IFS=',' read -ra RANGES <<< "$selection"
        
        for range in "${RANGES[@]}"; do
            range=$(echo "$range" | xargs) # trim whitespace
            
            if [[ "$range" =~ ^[0-9]+$ ]]; then
                # Single season
                local season_num=$(printf "%02d" "$range")
                if [[ -n "${season_episodes[$season_num]}" ]]; then
                    local episode_indices=(${season_episodes[$season_num]//,/ })
                    for idx in "${episode_indices[@]}"; do
                        selected_episodes+=("${episodes[$idx]}")
                    done
                fi
            elif [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
                # Season range
                local start=$(echo "$range" | cut -d'-' -f1)
                local end=$(echo "$range" | cut -d'-' -f2)
                for ((s=start; s<=end; s++)); do
                    local season_num=$(printf "%02d" "$s")
                    if [[ -n "${season_episodes[$season_num]}" ]]; then
                        local episode_indices=(${season_episodes[$season_num]//,/ })
                        for idx in "${episode_indices[@]}"; do
                            selected_episodes+=("${episodes[$idx]}")
                        done
                    fi
                done
            fi
        done
        
        if [ ${#selected_episodes[@]} -gt 0 ]; then
            echo "Selected ${#selected_episodes[@]} episodes from chosen seasons"
            select_episodes_within_seasons "$show_dir" "$show_name" "${selected_episodes[@]}"
            return $?
        else
            echo "❌ Invalid season selection. Try again."
        fi
    done
}

# Function to select specific episodes within already chosen seasons
select_episodes_within_seasons() {
    local show_dir="$1"
    local show_name="$2"
    shift 2
    local episodes=("$@")
    
    echo ""
    echo "📋 Episodes in selected seasons:"
    for i in "${!episodes[@]}"; do
        local episode_path="${episodes[$i]}"
        local relative_path=$(realpath --relative-to="$show_dir" "$episode_path")
        echo "  $((i+1))) $relative_path"
    done
    
    echo ""
    echo "Selection options:"
    echo "  • Episode numbers (e.g., 1,3,5-8)"
    echo "  • 'all' - Select all listed episodes"
    echo "  • 'q' - Go back to season selection"
    echo ""
    
    while true; do
        read -p "Select episodes: " selection
        
        if [[ "$selection" == "q" ]]; then
            return 1  # Go back to season selection
        fi
        
        if [[ "$selection" == "all" ]]; then
            copy_episodes_with_confirmation "$show_dir" "$show_name" "${episodes[@]}"
            return 0
        fi
        
        # Parse episode selection (same logic as original function)
        local selected_episodes=()
        IFS=',' read -ra RANGES <<< "$selection"
        
        for range in "${RANGES[@]}"; do
            range=$(echo "$range" | xargs) # trim whitespace
            
            if [[ "$range" =~ ^[0-9]+$ ]]; then
                # Single episode
                local idx=$((range-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#episodes[@]} ]; then
                    selected_episodes+=("${episodes[$idx]}")
                fi
            elif [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
                # Episode range
                local start=$(echo "$range" | cut -d'-' -f1)
                local end=$(echo "$range" | cut -d'-' -f2)
                for ((i=start; i<=end; i++)); do
                    local idx=$((i-1))
                    if [ $idx -ge 0 ] && [ $idx -lt ${#episodes[@]} ]; then
                        selected_episodes+=("${episodes[$idx]}")
                    fi
                done
            fi
        done
        
        if [ ${#selected_episodes[@]} -gt 0 ]; then
            copy_episodes_with_confirmation "$show_dir" "$show_name" "${selected_episodes[@]}"
            return 0
        else
            echo "❌ Invalid selection. Try again."
        fi
    done
}

# Function for episode selection and copying with season grouping for large shows
select_and_copy_episodes() {
    local show_dir="$1"
    local show_name="$2"
    shift 2
    local episodes=("$@")
    
    # If more than 20 episodes, use season-grouped interface
    if [ ${#episodes[@]} -gt 20 ]; then
        select_episodes_by_season "$show_dir" "$show_name" "${episodes[@]}"
        return $?
    fi
    
    # Original interface for smaller shows
    while true; do
        read -p "Select episodes (e.g., 1,3,5-8, S04, S03E05-S03E08, 'all' or 'q' to quit): " selection
        
        if [[ "$selection" == "q" ]]; then
            echo "Cancelled."
            return 0
        fi
        
        if [[ "$selection" == "all" ]]; then
            copy_episodes_with_confirmation "$show_dir" "$show_name" "${episodes[@]}"
            return 0
        fi
        
        # Parse selection
        local selected_episodes=()
        IFS=',' read -ra RANGES <<< "$selection"
        
        for range in "${RANGES[@]}"; do
            # Remove leading/trailing whitespace
            range=$(echo "$range" | xargs)
            
            if [[ "$range" =~ ^[0-9]+$ ]]; then
                # Simple number (episode index)
                local idx=$((range-1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#episodes[@]} ]; then
                    selected_episodes+=("${episodes[$idx]}")
                fi
            elif [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
                # Number range (episode indices)
                local start=$(echo "$range" | cut -d'-' -f1)
                local end=$(echo "$range" | cut -d'-' -f2)
                for ((i=start; i<=end; i++)); do
                    local idx=$((i-1))
                    if [ $idx -ge 0 ] && [ $idx -lt ${#episodes[@]} ]; then
                        selected_episodes+=("${episodes[$idx]}")
                    fi
                done
            elif [[ "$range" =~ ^[Ss][0-9]+$ ]]; then
                # Season selection (e.g., S04, s03)
                local season_num=$(echo "$range" | sed 's/[Ss]0*//')
                local season_pattern="S$(printf "%02d" $season_num)"
                for i in "${!episodes[@]}"; do
                    if [[ "$(basename "${episodes[$i]}")" =~ $season_pattern ]]; then
                        selected_episodes+=("${episodes[$i]}")
                    fi
                done
            elif [[ "$range" =~ ^[Ss][0-9]+[Ee][0-9]+-[Ss][0-9]+[Ee][0-9]+$ ]]; then
                # Season/Episode range (e.g., S03E05-S03E08)
                local start_ep=$(echo "$range" | cut -d'-' -f1 | sed 's/[Ss]0*/S/' | sed 's/[Ee]0*/E/')
                local end_ep=$(echo "$range" | cut -d'-' -f2 | sed 's/[Ss]0*/S/' | sed 's/[Ee]0*/E/')
                local in_range=false
                for episode in "${episodes[@]}"; do
                    local ep_name=$(basename "$episode")
                    if [[ "$ep_name" =~ $start_ep ]]; then
                        in_range=true
                    fi
                    if [ "$in_range" = true ]; then
                        selected_episodes+=("$episode")
                    fi
                    if [[ "$ep_name" =~ $end_ep ]]; then
                        in_range=false
                    fi
                done
            elif [[ "$range" =~ ^[Ss][0-9]+[Ee][0-9]+$ ]]; then
                # Single episode (e.g., S03E05)
                local ep_pattern=$(echo "$range" | sed 's/[Ss]0*/S/' | sed 's/[Ee]0*/E/')
                for episode in "${episodes[@]}"; do
                    if [[ "$(basename "$episode")" =~ $ep_pattern ]]; then
                        selected_episodes+=("$episode")
                    fi
                done
            fi
        done
        
        if [ ${#selected_episodes[@]} -gt 0 ]; then
            copy_episodes_with_confirmation "$show_dir" "$show_name" "${selected_episodes[@]}"
            return 0
        else
            echo "❌ Invalid selection. Try again."
        fi
    done
}

# Function to create copies for TV episodes and all associated files
copy_episodes() {
    local show_dir="$1"
    local show_name="$2"
    shift 2
    local episodes=("$@")
    
    local show_sync_dir="$SYNC_DIR/tv/$show_name"
    
    echo ""
    echo "Copying ${#episodes[@]} episodes and associated files..."
    
    for episode_path in "${episodes[@]}"; do
        # Get the base name without extension for finding associated files
        local episode_dir=$(dirname "$episode_path")
        local episode_basename=$(basename "$episode_path")
        local episode_name_no_ext="${episode_basename%.*}"
        
        # Extract the core episode identifier by removing quality/format tags and extension
        # This handles various filename formats more robustly
        local episode_core_pattern
        # Remove everything from the first [ bracket onwards, then remove extension
        if [[ "$episode_basename" =~ ^([^\[]+) ]]; then
            episode_core_pattern="${BASH_REMATCH[1]}"
            # Trim trailing whitespace
            episode_core_pattern=$(echo "$episode_core_pattern" | sed 's/[[:space:]]*$//')
        else
            # Fallback to removing just the extension
            episode_core_pattern="$episode_name_no_ext"
        fi
        
        # Find all associated files for this episode using the core pattern
        local associated_files=()
        while IFS= read -r -d '' file; do
            associated_files+=("$file")
        done < <(find "$episode_dir" -name "${episode_core_pattern}*" -type f -print0 2>/dev/null)
        
        if $DRY_RUN; then
            # Calculate total size of files to be copied
            local total_size=0
            for file in "${associated_files[@]}"; do
                if [ -f "$file" ]; then
                    local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                    total_size=$((total_size + file_size))
                fi
            done
            
            # Convert bytes to human readable format
            local human_size=$(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size}B")
            
            echo "🔍 DRY RUN: Would copy ${#associated_files[@]} files for episode ($human_size):"
            for file in "${associated_files[@]}"; do
                local relative_path=$(realpath --relative-to="$show_dir" "$file")
                echo "    📄 $relative_path"
            done
        else
            echo "📺 Copying ${#associated_files[@]} files for episode: $(basename "$episode_path")"  
            
            for file in "${associated_files[@]}"; do
                local relative_path=$(realpath --relative-to="$show_dir" "$file")
                local file_sync_path="$show_sync_dir/$relative_path"
                local file_sync_dir=$(dirname "$file_sync_path")
                
                mkdir -p "$file_sync_dir"
                
                if [ -L "$file_sync_path" ]; then
                    echo "    ⚠️  Already copied: $relative_path"
                elif [ -e "$file_sync_path" ]; then
                    echo "    ❌ File exists: $relative_path"
                else
                    cp "$file" "$file_sync_path"
                    # Ensure the copied file is readable by fixing permissions
                    chmod 644 "$file_sync_path" 2>/dev/null || true
                    echo "    ✅ Copied: $relative_path"
                fi
            done
        fi
        echo ""
    done
}

# Helper function to handle dry run confirmation and execution
copy_episodes_with_confirmation() {
    local show_dir="$1"
    local show_name="$2"
    shift 2
    local episodes=("$@")
    
    # First run in dry run mode
    local original_dry_run=$DRY_RUN
    DRY_RUN=true
    copy_episodes "$show_dir" "$show_name" "${episodes[@]}"
    
    # After dry run, offer to execute immediately
    if $original_dry_run; then
        echo ""
        echo "💡 Dry run complete. Would you like to execute these changes now?"
        read -p "Execute? (y/N): " -n 1 -r execute_choice
        echo ""
        
        if [[ $execute_choice =~ ^[Yy]$ ]]; then
            echo ""
            echo "🚀 Executing changes..."
            
            # Execute with DRY_RUN=false
            DRY_RUN=false
            copy_episodes "$show_dir" "$show_name" "${episodes[@]}"
        else
            echo "✅ Dry run complete. No changes made."
        fi
    fi
    
    # Restore original DRY_RUN state
    DRY_RUN=$original_dry_run
}

# Function to create copies for movies and all associated files
copy_movies() {
    local movies=("$@")
    
    echo ""
    echo "Creating copies for ${#movies[@]} movie(s) and associated files..."
    
    for movie_path in "${movies[@]}"; do
        # Get the base name without extension for finding associated files
        local movie_dir=$(dirname "$movie_path")
        local movie_basename=$(basename "$movie_path")
        local movie_name_no_ext="${movie_basename%.*}"
        
        # Extract the core movie identifier (e.g., "The Addams Family (1991) {tmdb-2907}")
        # This handles cases where files have different suffixes after the movie name
        local movie_core_pattern
        
        # Remove everything from the first '[' bracket onwards, then remove file extension
        # This handles patterns like: "Movie [format][audio][codec]-group.ext" -> "Movie"
        if [[ "$movie_basename" == *"["* ]]; then
            movie_core_pattern=$(echo "$movie_basename" | sed 's/\[.*$//')
        else
            # Fallback to removing just the extension
            movie_core_pattern="$movie_name_no_ext"
        fi
        
        # Trim any trailing whitespace
        movie_core_pattern=$(echo "$movie_core_pattern" | sed 's/[[:space:]]*$//')
        
        # Find all associated files for this movie using the core pattern
        local associated_files=()
        while IFS= read -r -d '' file; do
            associated_files+=("$file")
        done < <(find "$movie_dir" -name "${movie_core_pattern}*" -type f -print0 2>/dev/null)
        
        if $DRY_RUN; then
            # Calculate total size of files to be copied
            local total_size=0
            for file in "${associated_files[@]}"; do
                if [ -f "$file" ]; then
                    local file_size=$(stat -c%s "$file" 2>/dev/null || echo 0)
                    total_size=$((total_size + file_size))
                fi
            done
            
            # Convert bytes to human readable format
            local human_size=$(numfmt --to=iec-i --suffix=B $total_size 2>/dev/null || echo "${total_size}B")
            
            echo "🔍 DRY RUN: Would copy ${#associated_files[@]} files for movie ($human_size):"
            for file in "${associated_files[@]}"; do
                local movie_name=$(basename "$file")
                echo "    📄 $movie_name"
            done
        else
            echo "🎬 Copying ${#associated_files[@]} files for movie: $(basename "$movie_path")"
            
            for file in "${associated_files[@]}"; do
                local relative_path=$(realpath --relative-to="$MOVIE_SOURCE_DIR" "$file")
                local movie_sync_path="$SYNC_DIR/movies/$relative_path"
                local movie_sync_dir=$(dirname "$movie_sync_path")
                
                mkdir -p "$movie_sync_dir"
                
                if [ -L "$movie_sync_path" ]; then
                    echo "    ⚠️  Already copied: $relative_path"
                elif [ -e "$movie_sync_path" ]; then
                    echo "    ❌ File exists: $relative_path"
                else
                    cp "$file" "$movie_sync_path"
                    # Ensure the copied file is readable by fixing permissions
                    chmod 644 "$movie_sync_path" 2>/dev/null || true
                    echo "    ✅ Copied: $relative_path"
                fi
            done
        fi
        echo ""
    done
}

# Helper function to handle dry run confirmation and execution for movies
copy_movies_with_confirmation() {
    local movies=("$@")
    
    # First run in dry run mode
    local original_dry_run=$DRY_RUN
    DRY_RUN=true
    copy_movies "${movies[@]}"
    
    # After dry run, offer to execute immediately
    if $original_dry_run; then
        echo ""
        echo "💡 Dry run complete. Would you like to execute these changes now?"
        read -p "Execute? (y/N): " -n 1 -r execute_choice
        echo ""
        
        if [[ $execute_choice =~ ^[Yy]$ ]]; then
            echo ""
            echo "🚀 Executing changes..."
            
            # Execute with DRY_RUN=false
            DRY_RUN=false
            copy_movies "${movies[@]}"
        else
            echo "✅ Dry run complete. No changes made."
        fi
    fi
    
    # Restore original DRY_RUN state
    DRY_RUN=$original_dry_run
}

# Main script logic
find_media "$MEDIA_PATTERN" "$EPISODE_PATTERN" "$MEDIA_TYPE"

echo ""
echo "Current synced media:"
echo "📺 TV Shows:"
if [ -d "$SYNC_DIR/tv" ]; then
    find "$SYNC_DIR/tv" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read show_dir; do
        show_name=$(basename "$show_dir")
        episode_count=$(find "$show_dir" -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" 2>/dev/null | wc -l)
        if [ $episode_count -gt 0 ]; then
            echo "  $show_name ($episode_count episodes)"
        fi
    done
    
    # Calculate and display TV folder size
    tv_size=$(du -sh "$SYNC_DIR/tv" 2>/dev/null | cut -f1)
    tv_count=$(find "$SYNC_DIR/tv" -type f 2>/dev/null | wc -l)
    echo "📊 TV Total: $tv_size ($tv_count files)"
else
    echo "📊 TV Total: 0B (0 files)"
fi

echo ""
echo "🎬 Movies:"
if [ -d "$SYNC_DIR/movies" ]; then
    find "$SYNC_DIR/movies" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read movie_dir; do
        movie_name=$(basename "$movie_dir")
        echo "  $movie_name"
    done
    
    # Calculate and display Movies folder size
    movie_size=$(du -sh "$SYNC_DIR/movies" 2>/dev/null | cut -f1)
    movie_count=$(find "$SYNC_DIR/movies" -type f 2>/dev/null | wc -l)
    echo "📊 Movies Total: $movie_size ($movie_count files)"
else
    echo "📊 Movies Total: 0B (0 files)"
fi
