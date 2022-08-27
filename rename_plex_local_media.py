import glob
import os
import shutil


TV_PATH = r"/mnt/user/TV/"
MOVIE_PATH = r"/mnt/user/Movies/"

print(f"Updating TV shows from {TV_PATH} and movies from {MOVIE_PATH}")


def rename_show_poster(path):
    # go through all of our seasons
    for season in os.listdir(path):
        # if this is actually a season folder
        season_path = os.path.join(path, season)
        if "season" in season.lower() and os.path.isdir(season_path):
            # find our "folder.jpg" and copy and rename it as "SeasonXX"
            for file_name in os.listdir(season_path):
                if "folder" in file_name and file_name.endswith(".jpg"):
                    old_path = os.path.join(season_path, file_name)
                    new_path = os.path.join(season_path, season.replace(" ", "") + ".jpg")

                    shutil.copy(old_path, new_path)

    return True
