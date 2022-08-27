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


def rename_backdrop_file(path, movie=False):
    backdrop_list = [file for file in os.listdir(path) if "backdrop" in file]

    if len(backdrop_list) == 0:
        return False

    if movie:
        movie_file_name = [file for file in os.listdir(path) if file.endswith(".mkv")]
        if len(movie_file_name) != 1:
            print(f"{path} does not have a single .mkv file")
            return False

        movie_file_name = movie_file_name[0].split(".mkv")[0]

        for image_type in ["backdrop", "landscape", "logo", "poster", "banner", "clearart", "discart"]:
            for extension in [".jpg", ".png"]:
                file_path = os.path.join(path, f"{movie_file_name}-{image_type}{extension}")
                if os.path.isfile(file_path):
                    shutil.copy(file_path, os.path.join(path, f"{image_type}{extension}"))
                    os.remove(file_path)

            # delete any posters, backdrops, logos, etc that are NOT our movie's file name
            for file in os.listdir(path):
                if "-" in file and movie_file_name not in file:
                    os.remove(os.path.join(path, file))

        backdrop_list = [file for file in os.listdir(path) if "backdrop" in file]

    if backdrop_list:

        # if we only have one entry in the list of backdrop files
        # then we will make sure that it is labelled "backdrop.jpg"
        if len(backdrop_list) == 1:
            if "backdrop.jpg" in backdrop_list:
                pass
            else:
                old_path = os.path.join(path, backdrop_list[0])
                new_path = os.path.join(path, "backdrop.jpg")

                shutil.copy(old_path, new_path)

        # otherwise, we will delete all "backdrop.jpg" and "backdropX.jpg" until the highest X
        else:
            # get our list of X for backdropX
            backdrop_nums = [int(b.split("backdrop")[-1].split(".jpg")[0]) for b in backdrop_list if
                             b != "backdrop.jpg"]
            backdrop_nums.sort()

            good_backdrop_file = f"backdrop{backdrop_nums[-1]}.jpg"

            # go through all of our backdrop files
            # and delete all backdrop files that are not our highest X
            for backdrop_file in backdrop_list:
                if backdrop_file != good_backdrop_file:
                    os.remove(os.path.join(path, backdrop_file))

            # now that all other backdrop files have been deleted, we can rename our backdropX.jpg to be backdrop.jpg
            old_path = os.path.join(path, good_backdrop_file)
            new_path = os.path.join(path, "backdrop.jpg")

            shutil.copy(old_path, new_path)

            # and finally, delete our backdropX.jpg
            os.remove(os.path.join(path, good_backdrop_file))

    return True
def remove_tdarrcache_files(path):
    for filename in glob.iglob(path + '**/*TdarrCache*', recursive=True):
        os.remove(filename)

    return True
