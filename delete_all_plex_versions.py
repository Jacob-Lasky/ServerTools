import glob
import os
import shutil
import time


TV_PATH = r"/mnt/user/TV/"
MOVIE_PATH = r"/mnt/user/Movies/"

print(f"Deleting 'Plex Versions' from {TV_PATH} and {MOVIE_PATH}")


def delete_plex_versions(path, dryRun=False):
    plexVersionsPath = os.path.join(path, "Plex Versions")
    # if this is actually a season folder and "Plex Versions" exists within it, then delete it
    if os.path.isdir(plexVersionsPath):
        print(f"Removing {plexVersionsPath}")
        if dryRun:
            print("DRY RUN, NOTHING DELETED")
            time.sleep(3)
        else:
            shutil.rmtree(plexVersionsPath)

    return True


# work with TV shows #
shows = list(os.listdir(TV_PATH))

# go through all of our shows
for show in shows:
    print(f"Checking for 'Plex Versions' in the show: {show}")

    show_path = os.path.join(TV_PATH, show)
    # go through all of our seasons
    for subDirs in os.listdir(show_path):
        season_path = os.path.join(show_path, subDirs)

        delete_plex_versions(season_path)

# work with movies directory #
movies = list(os.listdir(MOVIE_PATH))

# go through all of our movies
for movie in movies:
    print(f"Checking for 'Plex Versions' in the movie: {movie}")

    movie_path = os.path.join(MOVIE_PATH, movie)

    delete_plex_versions(movie_path)

print("DONE")
