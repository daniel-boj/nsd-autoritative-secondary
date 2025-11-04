# Disclaimer
### Sientanse libres para descargar y copiar lo que quieran del repo, pero lo dejo protegido para que no haya cambios imprevistos.
### Pueden realizr un fork y trabajar tranquilamente con si fork propio.
### Cualquier recomendación o sugerencia, no duden en contactar conmigo
# 1 Diseño de la solución
## 1.1 Implementación Aislada: Capa de Contenedores Docker
Para maximizar la robustez, portabilidad y mantenibilidad del servicio, se ha implementado el servidor DNS secundario dentro de un ambiente en contenedores mediante **Docker**. Este modelo de diseño representa tanto una modernización en la arquitectura de los servidores, como , un aporte de beneficios tangibles y críticos para un servicio de infraestructura.

### **1.1.1 Principio de un Servico, un Contenedor

En lugar de instalar el servicio NSD directamente sobre el sistema operativo del servidor (host), lo encapsulamos en un contenedor autosuficiente, independiente y aislado del entorno. Esto sigue el principio de **inmutabilidad**: el contenedor es una unidad predecible y consistente que contiene la aplicación, sus dependencias y su configuración.

### **1.1.2 Ventajas Clave de la Containerización en un Servicio DNS**

- **1. Aislamiento y Seguridad Mejorados:**
    - **Sandboxing ->** El proceso de NSD se ejecuta en un espacio de nombres (namespace) aislado. Un potencial exploit o vulnerabilidad en el servicio DNS estaría confinado dentro del contenedor, dificultando significativamente un escape hacia el sistema host subyacente.
    - **Reducciónde la Superficie de Ataque ->** La imagen del contenedor esta personalizada y creada exprofeso, además, se basa en un SO minimalista y enfocado a la seguridad (*Debian Trixie-Slim*), eliminando miles de paquetes y herramientas innecesarias que podrían ser vectores de ataque en una instalación tradicional.
- **2. Consistencia y Reproducibilidad Absolutas :**
    - **"Runs Anywhere" ->** La misma imagen de Docker ejecutándose garantiza un comportamiento idéntico. Se eliminan los problemas del tipo "_pero si en mi máquina funciona_", causados por diferencias en librerías, versiones del SO o configuraciones del entorno.
    - **Configuracion como Código (CaC) ->** El `Dockerfile` (que define cómo construir la imagen) y el `docker-compose.yml` (que define cómo ejecutar el contenedor) documentan de forma ejecutable y versionable la configuración completa del servicio.
- **3. Gestión Simplificada y Despliegues Ágiles:**
    - **Despliegue y Rollback Inmediatos ->** Actualizar el servicio es tan simple como descargar una nueva imagen y reiniciar el contenedor. Si surge un problema, revertir a la versión anterior es igual de rápido, simplemente reiniciando el contenedor con la imagen previa.
    - **Facilidad de Replicación ->** Desplegar un nuevo servidor secundario en el futuro, o incluso un tercero en otra región, se convierte en un proceso trivial: clonar la configuración, levantar el contenedor y asegurar la conectividad para las transferencias de zona.
- **4. Independencia del Sistema Host:**
    - **Libertad de Actualización del Host ->** Podemos realizar actualizaciones de seguridad o del kernel del sistema operativo del host sin preocuparnos por romper dependencias críticas del servicio DNS. El contenedor es un entorno autónomo.
    - **Múltiples Servicios sin Conflictos ->** En el mismo host físico podríamos ejecutar otros servicios en sus propios contenedores (un monitor, un proxy, etc.) sin riesgo de conflictos de puertos o librerías, ya que cada contenedor tiene su red y sistema de archivos aislado.
- **5. Optimización de Recursos y Eficiencia:**
    - **Baja Sobrecarga (Overhead) ->** A diferencia de una máquina virtual completa, un contenedor comparte el kernel del host, lo que se traduce en un arranque casi instantáneo y un consumo mínimo de recursos CPU y RAM adicionales.
    - **Logs Centralizados ->** Los logs (`stdout`/`stderr`) del contenedor pueden ser redirigidos fácilmente a un sistema centralizado de logs (como ELK o Loki) mediante el driver de Docker, facilitando la monitorización y el troubleshooting.
# 2 Manual de Implementación
## Servidor DNS autoritativo secundario con NSD y Docker
Este manual sirve como guía de despliegue completa del servidor DNS utilizando la pila containerizada mediante Docker.
## 2.1 Prerrequisitos
- Servidor desplegado con Docker y Docker Compose instalados.
- Puertos TCP y UDP 53 abiertos,
- Clave API o TSGI compartida con el servidor maestro para la transferencia y sincronización segura de zonas.
-  `systemd-resolver` deshabilitado y *zona horaria* correctamente configurada.
## 2.2 Estructura del Proyecto
```bash
/docker/dns4.e-osca.com/
└── nsd.wedreams
    ├── config
    │   └── nsd.conf
    ├── data
    │   └── zones
    ├── docker-compose.yml
    ├── image
    │   └── Dockerfile
    ├── README.nd
    └── scripts
        ├── check_zones.sh
        ├── entrypoint.sh
        └── load-zones.sh
```
Para descargar el repositorio hay que usar una de las siguientes opciones:
1. HTTPS -> https://gitdreams.e-osca.com/dani/nsd-wedreams.git
2. SSH -> git@172.16.5.37:dani/nsd-wedreams.git
### 2.2.1 Docker
1. Se usa una imagen Docker personalizada que genera un servicio en base a un servidor de alto rendimiento y muy bajo consumo.
2. La personalización del entorno containerizado se crea mediante un `docker-compose-yml` permitiendo una configuración sencilla y muy flexible.
3. El inicio y configuración del servicio NSD se automatiza mediante el uso de scripts, tanto de *entrypoint* como de carga y comprobación de zonas.
## 2.3 Preparar el servidor host
Entendiendo qe ya se ha realizado la configuración básica y el hardening, pasamos a los pasos específicos:
1. Para que NSD pueda usar el puerto 53, debemos detener el *resolver* nativo del host -> `sudo systemctl disable --now systemd-resolver`.
2. Instalamos Docker y Docker compose siguiendo la guía oficial -> [Instalación de Docker en Debian](https://docs.docker.com/engine/install/debian/)
3. Configuramos la zona horaria -> `timedatectl set-timezone Europe/Madrid`
## 2.4 Clonación del repositorio y configuración
1. **Clonamos el repositorio** mediante https o ssh ->
```
# No usar solo un tipo de descarga, HTTPS o SSH
git clone https://gitdreams.e-osca.com/dani/nsd-wedreams.git | git@172.16.5.37:dani/nsd-wedreams.git
cd nsd.wdreams
cp env.example .env
```
2. **Completamos la configuración de las variables de entorno** -> Los valores de estos campos están almacenados como credenciales de seguridad y nunca se comparten en el repositorio.
```bash
POWERDNS_MASTER="dirección IP del servidor master"
API_KEY="API key para acceder a la transferencia de zonas"
```
## 2.5 Configurar permisos en el servidor Master
Para que el nuevo servidor pueda acceder de forma segura a la API del servidor master, debemos permitir la IP del nuevo host en los archivos de configuración, es este caso, del servidor PowerDNS. 

Si se cambiara el tipo de solución para el servidor maestro, habría que realizar los mismos pasos para adaptados al nuevo tipo de servidor.

1. **Acceso a puertos** -> Concederemos acceso a la IP del host NSD a los puertos
	1. API: 8081/tcp
2. **Archivo de configuración de PowerDNS -> **
	1. Accedemos al servidor PowerDNS
	2. Editamos el archivo de configuración `/etc/powerdns/pdns.conf`
	3. Añadimos la IP del host NSD en los siguientes campos:
```bash
api=yes
api-key=******* # API Key

allow-axfr-ips= # Añadimos la nueva IP a la lista
default-soa-name= # Nombre del dominio master
master=yes
also-notify= # Añadimos la nueva IP a la lista
```
3. Reiniciamos el servicio, `systemctl restart pdns.service`
## 2.6 Levantar el servicio y finalizar la configuración
1. Aunque el archivo `docker-compose.yml` está preparado por defect, es recomendable revisarlo y realizar cualquier cambio o personalización pertinenente:
	- **Imagen:** Especifica la imagen personalizada de Docker Hub.
	- **Volúmenes:** Mapea `./data` para persistir zonas y logs, y `./config` para la configuración.
	- **Puertos:** Expone el puerto 53 (UDP/TCP) del contenedor en el host.
	- **Variables de Entorno:** Inyecta las configuraciones desde el archivo `.env`.
	- **Networks:** Personaliza la red que compartirán el host y Docker.
2. **Desplegamos el Servicio:** `docker compose up -d`
3. **Monitorización del despliegue:** Ejecutamos `docker logs <container_name>` para monitorizar cómo se ejecuta el script de *entrypoint*.
4. **Ejecutar el script de carga de zonas:** Tras la finalización de la transferencia de zonas que ejecuta el entry point, procedemos a ejecutar el srcipt de carga de datos -> `docker exec `
5. **Comprobar la transferencia de zonas:** Una vez finalizada la ejecución de los scripts de carga, podemos entrar al contenedor para comprobar la correcta transferencia de las zonas ->
```bash
# Acceder al contenedor
docker-compose exec <container_name> /bin/bash
# Dentro del contenedor, comprobar las zonas
nsd-control zonestatus
nsd-control zonestatus <nombre_zona>
```
6. **Validar Respuestas DNS:** Desde el host o en un cliente de confianza, hacemos una petición apuntando directamente al servidor NSD ->
```bash
dig @<IP_DEL_HOST> dominio.com SOA
```
## 2.7 Operativa
1. Reinicio del servicio -> `docker restart <container_name>`
2. Detener el servicio -> `docker compose down`
3. Acceso a logs -> `docker logs <container_name>`
4. Actualizar la imagen tras un *push* a Docker Hub ->
```bash
docker compose down
docker compose pull
docker compose up -d
```
## 2.8 Enlaces de interés
[Manual NSD](https://nsd.docs.nlnetlabs.nl/en/latest/index.html)

