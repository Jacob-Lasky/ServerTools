FROM python:3

WORKDIR /app

COPY . /app

CMD ["python", "standalone_scripts/clean_plex_local_media.py"]
