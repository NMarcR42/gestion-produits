FROM php:8.2-apache

# Installation des dépendances système requises pour PostgreSQL et la gestion d'images si besoin
RUN apt-get update && apt-get install -y \
    libpq-dev \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copie des sources de l'application dans le dossier d'Apache
COPY www/ /var/www/html/

# Configuration des permissions pour les dossiers d'images/uploads
RUN chown -R www-data:www-data /var/www/html/uploads /var/www/html/img \
    && chmod -R 755 /var/www/html/uploads /var/www/html/img

# Activation du module rewrite d'Apache (souvent utile en PHP)
RUN a2enmod rewrite

EXPOSE 80