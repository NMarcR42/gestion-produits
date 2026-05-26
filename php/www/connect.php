<?php
$db_type  = getenv('DB_TYPE') ?: 'mysql'; 
$host     = getenv('DB_HOST') ?: 'db'; // Par défaut 'db'
$username = getenv('DB_USER') ?: 'root';
$password = getenv('DB_PASS') ?: 'root';
$db_name  = getenv('DB_NAME') ?: 'gestion_produits';
$port     = getenv('DB_PORT') ?: ($db_type === 'pgsql' ? '5432' : '3306');

try {
    if ($db_type === 'pgsql') {
        $dsn = "pgsql:host=$host;port=$port;dbname=$db_name";
    } else {
        $dsn = "mysql:host=$host;port=$port;dbname=$db_name;charset=utf8";
    }

    $db = new PDO($dsn, $username, $password);
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

} catch (PDOException $e) {
    die("Erreur de connexion à la base de données : " . $e->getMessage());
}
?>