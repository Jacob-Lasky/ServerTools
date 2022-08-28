import io
import os
import re

from PIL import Image, ImageDraw, ImageFont

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


def calculate_true_fontsize(img, caption, font_type="impact.ttf", img_fraction=0.8):
    """
    :param img_fraction: proportion of image for the text to fit into
    """
    fontsize = 1  # starting font size

    font = ImageFont.truetype(font_type, fontsize)
    while font.getsize(caption)[0] < img_fraction * img.size[0]:
        # iterate until the text size is just larger than the criteria
        fontsize += 1
        font = ImageFont.truetype(font_type, fontsize)

    # optionally de-increment to be sure it is less than criteria
    fontsize -= 1

    return fontsize


def get_img_text(img_path):
    with io.open(img_path, "rb") as image_file:
        content = image_file.read()

    image = vision.Image(content=content)

    response = client.text_detection(image=image)
    return response


def add_text_to_foreground(img_path, caption):
    caption = caption.replace(",", ",\n").replace(
        ":", ":\n"
    )  # add line breaks where we have commas or colons

    with Image.open(img_path) as img:
        W, H = img.size

        d = ImageDraw.Draw(img)
        font = ImageFont.truetype(
            "impact.ttf", size=calculate_true_fontsize(img, caption)
        )
        w, h = d.textsize(caption, font)
        d.text(
            ((W - w) / 2, (H - h) / 2),
            caption,
            fill="white",
            font=font,
            stroke_width=2,
            stroke_fill="black",
        )
        img.save(img_path)


def sanitize_movie_str(movie):
    # Movie, The (2000) {imdb-123456} --> Movie, The
    movie_str = re.split(" (\(\d{4}\)) ", movie)[0]

    # Movie, (The, A, An) --> (The, A, An) Movie
    if re.search("(, The|, A|, An)$", movie_str):
        movie_split = re.split("(, The|, A|, An)$", movie_str)
        movie_str = f"{movie_split[1].replace(', ', '')} {movie_split[0]}"

    return movie_str


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

    if (
        movie not in json_db["data"]
        or json_db["data"][movie]["backdrop_result"] == "NO BACKDROP.JPG FILE"
    ):
        json_db["data"][movie] = {}

        if os.path.exists(img_path):
            json_db["data"][movie]["backdrop_last_modified_epoch"] = os.path.getmtime(
                img_path
            )
            json_db["data"][movie][
                "last_image_search_epoch"
            ] = 0  # we've never searched for it
            json_db["data"][movie]["backdrop_result"] = ""

        else:
            json_db["data"][movie]["backdrop_result"] = "NO BACKDROP.JPG FILE"
            continue

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

        movie_str = sanitize_movie_str(movie)

        response = get_img_text(img_path)
        result, percent_match = match_movie_text(movie_str, response, verbose)

        json_db["data"][movie]["backdrop_text"] = response.full_text_annotation.text
        json_db["data"][movie]["backdrop_result"] = result
        json_db["data"][movie]["backdrop_percent_match"] = percent_match

        print(result)
        if result == "NO TEXT FOUND":
            print(f"Adding caption to {movie}")
            add_text_to_foreground(img_path, caption=movie_str)
            break

        clean_text = response.full_text_annotation.text.replace("\n", " ")

        if verbose:
            print(f"- {result} - {clean_text}")

    else:
        continue

    json_db["data"][movie]["last_image_search_epoch"] = dt.datetime.now().timestamp()

# finally, dump our new json_db file
with open(db_path, "w") as f:
    dump(json_db, f, indent=4)
