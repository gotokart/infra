# Railway Infrastructure

## Services
- backend: Spring Boot API
- MySQL: Database

## Environment Variables (backend service)
SPRING_DATASOURCE_URL=jdbc:mysql://<host>:<port>/railway
SPRING_DATASOURCE_USERNAME=root
SPRING_DATASOURCE_PASSWORD=<from Railway>
SPRING_JPA_HIBERNATE_DDL_AUTO=update
SPRING_JPA_DATABASE_PLATFORM=org.hibernate.dialect.MySQLDialect
SPRING_JPA_SHOW_SQL=false
SPRING_JACKSON_SERIALIZATION_FAIL_ON_EMPTY_BEANS=false
SPRING_JACKSON_DEFAULT_PROPERTY_INCLUSION=non_null

## Deployment
- Auto-deploy on push to main via Railway GitHub integration
- Backend URL: https://backend-production-e13e2.up.railway.app
