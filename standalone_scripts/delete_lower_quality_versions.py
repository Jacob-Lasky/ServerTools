from pathlib import Path
from plexapi.server import PlexServer
import os
import json


with open("variables.json", "r") as f:
    variables = json.load(f)

baseurl = variables["baseurl"]
token = variables["token"]
plex = PlexServer(baseurl, token)

TV_PATH = variables["TV_PATH"]
MOVIE_PATH = variables["MOVIE_PATH"]


def remove_duplicate_episodes_and_movies(dry_run=True):
    remove_duplicate_episodes(
        library=plex.library.section("TV Shows"), abs_path=TV_PATH, dry_run=dry_run
    )
    remove_duplicate_movies(
        library=plex.library.section("Movies"), abs_path=MOVIE_PATH, dry_run=dry_run
    )


def remove_duplicate_movies(library, abs_path, dry_run=True):
    # go through each of our movies
    for movie in library.search():
        movieStr = movie.title
        if len(movie.media) > 1:

            print(f"DUPLICATE MOVIE FOUND: {movieStr}")

            remove_lowest_bitrate_media(
                mediaFiles=movie, abs_path=abs_path, dry_run=dry_run
            )


def remove_duplicate_episodes(library, abs_path, dry_run=True):
    # go through each of our series
    for series in library.search():
        seriesStr = series.title
        # go through each season
        for season in series.seasons():
            seasonStr = season.title
            # go through each episode
            for episode in season.episodes():
                # if we have more than one file for this episode, then we'll get the bitrates for each episode and keep only the highest bitrate
                if len(episode.media) > 1:
                    episodeStr = episode.title

                    print(
                        f"DUPLICATES EPISODE FOUND: {seriesStr} - {seasonStr} - {episodeStr}"
                    )

                    remove_lowest_bitrate_media(
                        mediaFiles=episode, abs_path=abs_path, dry_run=dry_run
                    )


def remove_lowest_bitrate_media(mediaFiles, abs_path, dry_run=True):
    # go through each media file and create a dictonary of {file: bitrate}
    mediaDict = dict()
    maxBitrate = -1
    for file_n, file in enumerate(mediaFiles.media):
        # go from Docker volume to absolute path
        abs_file_name = os.path.join(
            abs_path, "/".join(os.path.normpath(file.parts[0].file).split(os.sep)[2:])
        )

        bitrate = file.bitrate
        mediaDict[abs_file_name] = {"bitrate": bitrate}
        if bitrate > maxBitrate:
            maxBitrateFile = file_n
            maxBitrate = bitrate
            maxBitrateFile_n = file_n

    # go through our new dictionary and delete the files whose bitrates are not the max
    for file_n, file in enumerate(mediaDict):
        if maxBitrateFile_n == file_n:  # don't need to check this file
            print(f"Keeping this file: {file}")
            continue

        print(f"Attempting to remove: {file}")

        if "Plex Versions" in file:
            print(
                f"-SKIPPING \n --Reason for skip: This is a plex version, remove with delete_all_plex_versions.py"
            )
            continue

        if not os.path.isfile(file):
            print(f"-COULD NOT FIND: {file}")
            continue

        if mediaDict[file]["bitrate"] < maxBitrate:
            print(
                f"-DELETING {file} \n --Reason for deletion: media bitrate of {mediaDict[file]['bitrate']} < max bitrate of {maxBitrate}"
            )

            # last check by file name
            if maxBitrateFile != file:
                if dry_run:
                    print("-DRY RUN: NO FILES DELETED")
                else:
                    # remove our file and also remove the associated .nfo
                    os.remove(file)
                    nfo_file = os.path.join(
                        os.path.normpath(os.path.split(file)[0]),
                        Path(file).stem + ".nfo",
                    )
                    if os.path.isfile(nfo_file):
                        os.remove(nfo_file)


remove_duplicate_episodes_and_movies(dry_run=False)

print("DONE")
