package com.ecoair;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Punto de entrada del backend eco-air-backend.
 *
 * La linea "Started EcoAirApplication in X seconds" que emite Spring Boot es
 * la firma que se usa como evidencia de arranque en el taller.
 */
@SpringBootApplication
public class EcoAirApplication {

    public static void main(String[] args) {
        SpringApplication.run(EcoAirApplication.class, args);
    }
}
