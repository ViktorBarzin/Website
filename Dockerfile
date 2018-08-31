FROM python:3.7.0

WORKDIR /blog
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# COPY docs ./
CMD mkdocs serve -a 0.0.0.0:8000
