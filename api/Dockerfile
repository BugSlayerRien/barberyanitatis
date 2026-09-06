# PHP API for Render (Apache + PDO PostgreSQL + cURL)
FROM php:8.2-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        libzip-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev \
        ca-certificates \
    && docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j$(nproc) pdo_pgsql pgsql zip gd \
    && a2enmod rewrite headers setenvif \
    && rm -rf /var/lib/apt/lists/*

# Pass Authorization into PHP. CGIPassAuth is directory-only (see the conf file).
COPY apache-pass-authorization.conf /etc/apache2/conf-available/pass-authorization.conf
RUN a2enconf pass-authorization \
    && sed -i '1i LimitRequestFieldSize 32768\nLimitRequestLine 16384' /etc/apache2/apache2.conf

# App lives at document root so URLs are https://host/auth.php
COPY . /var/www/html/

RUN rm -f /var/www/html/apache-pass-authorization.conf \
    && mkdir -p /var/www/html/uploads/face_scans \
        /var/www/html/uploads/profiles \
        /var/www/html/uploads/barbers \
        /var/www/html/storage \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 775 /var/www/html/uploads /var/www/html/storage \
    && printf 'display_errors=Off\nlog_errors=On\n' > /usr/local/etc/php/conf.d/zzz-production.ini

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENV APACHE_DOCUMENT_ROOT=/var/www/html
EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
