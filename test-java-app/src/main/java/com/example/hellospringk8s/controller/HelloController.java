package com.example.hellospringk8s.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.http.ResponseEntity;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@RestController
public class HelloController {

    private final Random random = new Random();

    @GetMapping("/")
    public ResponseEntity<Map<String, String>> hello() {
        Map<String, String> response = new HashMap<>();
        response.put("message", "Hello from Spring Boot K8s with APM!");
        response.put("timestamp", String.valueOf(System.currentTimeMillis()));
        return ResponseEntity.ok(response);
    }

    @GetMapping("/api/hello")
    public ResponseEntity<Map<String, String>> apiHello() {
        Map<String, String> response = new HashMap<>();
        response.put("message", "Hello from API endpoint!");
        response.put("timestamp", String.valueOf(System.currentTimeMillis()));
        return ResponseEntity.ok(response);
    }

    @GetMapping("/api/slow")
    public ResponseEntity<Map<String, String>> slowEndpoint() throws InterruptedException {
        // Simulate slow operation
        Thread.sleep(random.nextInt(2000) + 500);
        
        Map<String, String> response = new HashMap<>();
        response.put("message", "This was a slow operation");
        response.put("duration", "500-2500ms");
        return ResponseEntity.ok(response);
    }

    @GetMapping("/api/error")
    public ResponseEntity<Map<String, String>> errorEndpoint() {
        if (random.nextBoolean()) {
            throw new RuntimeException("Random error occurred!");
        }
        
        Map<String, String> response = new HashMap<>();
        response.put("message", "No error this time");
        return ResponseEntity.ok(response);
    }
}
