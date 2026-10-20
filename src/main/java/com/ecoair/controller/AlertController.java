package com.ecoair.controller;

import com.ecoair.model.EnvironmentalAlert;
import com.ecoair.repository.EnvironmentalAlertRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/alerts")
public class AlertController {

    private final EnvironmentalAlertRepository repository;

    public AlertController(EnvironmentalAlertRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    public List<EnvironmentalAlert> all() {
        return repository.findAll();
    }

    @GetMapping("/severity/{severity}")
    public List<EnvironmentalAlert> bySeverity(@PathVariable String severity) {
        return repository.findBySeverity(severity);
    }

    @PostMapping
    public ResponseEntity<EnvironmentalAlert> ingest(@RequestBody EnvironmentalAlert alert) {
        return ResponseEntity.ok(repository.save(alert));
    }
}
