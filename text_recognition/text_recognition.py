import io
import os

import datetime as dt

from difflib import SequenceMatcher
from json import load, dump

from google.cloud import vision

MOVIE_PATH = r"\\192.168.86.183\Movies"
local_path = r"\\192.168.86.183\misc\user_scripts\text_recognition"
db_name = "image_results_database.json"
db_path = os.path.join(local_path, db_name)

os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = os.path.join(
    r"\\192.168.86.183\misc\user_scripts\text_recognition", "gcloud-authentication.json"
)
client = vision.ImageAnnotatorClient()
image = vision.Image()


def match_movie_text(movie, response, verbose=False):
    sanitized_movie = movie.split(" (")[0].lower()
    sanitized_text = response.full_text_annotation.text.replace("\n", " ").lower()

    percent_match = round(
        SequenceMatcher(a=movie, b=response.full_text_annotation.text).ratio(), 3
    )

    # different cases
    if len(sanitized_text) == 0:
        if verbose:
            print("No text found in image")

        result = "NO TEXT FOUND"

    if sanitized_text == sanitized_movie:
        if verbose:
            print("Found perfect match.")

        result = "PERFECT"

    elif sanitized_movie in sanitized_text:
        if verbose:
            print("Found SUB match.")

        result = "SUB MATCH"
    else:
        if verbose:
            print("====")
            print(f"Movie name: {sanitized_movie}")
            print(f"Image text: {sanitized_text}")

        result = "NO MATCH"

    return result, percent_match


def get_img_text(img_path):
    with io.open(img_path, "rb") as image_file:
        content = image_file.read()

    image = vision.Image(content=content)

    response = client.text_detection(image=image)
    return response


# initialize our "database"
if not os.path.exists(db_path):
    json_db = {"version": "1.0.0", "data": {}}
    with open(db_path, "w") as f:
        dump(json_db, f, indent=4)

with open(db_path, "r") as f:
    json_db = load(f)

verbose = False
for n, movie in enumerate(os.listdir(MOVIE_PATH)):
    folder = os.path.join(MOVIE_PATH, movie)
    img_path = os.path.join(folder, "backdrop.jpg")

    if movie not in json_db["data"]:
        json_db["data"][movie] = {}
        json_db["data"][movie]["backdrop_last_modified_epoch"] = os.path.getmtime(
            img_path
        )
        json_db["data"][movie][
            "last_image_search_epoch"
        ] = 0  # we've never searched for it

    # movie is in our db, so we need to check and see if we last searched for this image before it was last modified
    if (
        json_db["data"][movie]["backdrop_last_modified_epoch"]
        > json_db["data"][movie]["last_image_search_epoch"]
    ):
        # do our search
        if json_db["data"][movie]["last_image_search_epoch"] == 0:
            print(f"{movie}: performing first search.")

        else:
            print(f"{movie}: backdrop was modified since the last search.")

        response = get_img_text(img_path)
        result, percent_match = match_movie_text(movie, response, verbose)

        json_db["data"][movie]["backdrop_text"] = response.full_text_annotation.text
        json_db["data"][movie]["backdrop_result"] = result
        json_db["data"][movie]["backdrop_percent_match"] = percent_match

        clean_text = response.full_text_annotation.text.replace("\n", " ")

        if verbose:
            print(f"- {result} - {clean_text}")

    else:
        continue

    json_db["data"][movie]["last_image_search_epoch"] = dt.datetime.now().timestamp()

# finally, dump our new json_db file
with open(db_path, "w") as f:
    dump(json_db, f, indent=4)
