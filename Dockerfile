FROM php:alpine

COPY app/ /app/
WORKDIR /app/

CMD [ "php", "-S", "0.0.0.0:80" ]
