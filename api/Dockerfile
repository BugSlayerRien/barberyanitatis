# PHP API for Render (Apache + PDO PostgreSQL + cURL)
FROM php:8.2-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libpq-dev \
        libzip-dev \
        zlib1g-dev \
        libcurl4-openssl-dev \
        ca-certificates \
    && docker-php-ext-install -j$(nproc) pdo_pgsql pgsql zip \
    && a2enmod rewrite headers \
    && printf '%s\n' \
        'CGIPassAuth On' \
        'SetEnvIf Authorization "(.+)" HTTP_AUTHORIZATION=$1' \
        'SetEnvIf Authorization "(.+)" REDIRECT_HTTP_AUTHORIZATION=$1' \
        '<Directory /var/www/html>' \
        '    AllowOverride FileInfo AuthConfig Limit' \
        '    CGIPassAuth On' \
        '</Directory>' \
        > /etc/apache2/conf-available/pass-authorization.conf \
    && a2enconf pass-authorization \
    && rm -rf /var/lib/apt/lists/*

# App lives at document root so URLs are https://host/auth.php
COPY . /var/www/html/

RUN mkdir -p /var/www/html/uploads/face_scans \
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
