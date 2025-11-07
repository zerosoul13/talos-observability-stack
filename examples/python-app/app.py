#!/usr/bin/env python3

"""
Python Flask Application with Prometheus Metrics
Demonstrates observability integration with structured logging and metrics
"""

import json
import logging
import random
import time
from datetime import datetime
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from werkzeug.middleware.dispatcher import DispatcherMiddleware
from prometheus_client import make_wsgi_app

# Initialize Flask app
app = Flask(__name__)

# Configure JSON logging
class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'level': record.levelname,
            'message': record.getMessage(),
            'service': 'python-app',
            'logger': record.name,
        }

        # Add extra fields if available
        if hasattr(record, 'extra_fields'):
            log_data.update(record.extra_fields)

        return json.dumps(log_data)

# Setup logging
handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logger = logging.getLogger('python-app')
logger.addHandler(handler)
logger.setLevel(logging.INFO)

# Prometheus metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)

active_requests = Gauge(
    'active_requests',
    'Number of active requests'
)

business_operations_total = Counter(
    'business_operations_total',
    'Total business operations',
    ['operation', 'status']
)

# Middleware for metrics and logging
@app.before_request
def before_request():
    request.start_time = time.time()
    active_requests.inc()

    # Log incoming request
    extra_fields = {
        'method': request.method,
        'path': request.path,
        'remote_addr': request.remote_addr,
    }
    logger.info('incoming_request', extra={'extra_fields': extra_fields})

@app.after_request
def after_request(response):
    # Calculate request duration
    request_duration = time.time() - request.start_time

    # Record metrics
    http_requests_total.labels(
        method=request.method,
        endpoint=request.path,
        status=response.status_code
    ).inc()

    http_request_duration_seconds.labels(
        method=request.method,
        endpoint=request.path
    ).observe(request_duration)

    active_requests.dec()

    # Log response
    extra_fields = {
        'method': request.method,
        'path': request.path,
        'status': response.status_code,
        'duration_ms': request_duration * 1000,
    }
    logger.info('request_completed', extra={'extra_fields': extra_fields})

    return response

# Routes

@app.route('/')
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'python-app',
        'version': '1.0.0',
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    })

@app.route('/api/data')
def get_data():
    """Sample data endpoint with business logic"""
    # Simulate processing
    processing_time = random.uniform(0.05, 0.15)
    time.sleep(processing_time)

    # Simulate success/failure (90% success rate)
    success = random.random() > 0.1

    if not success:
        business_operations_total.labels(
            operation='data_fetch',
            status='failure'
        ).inc()

        extra_fields = {'reason': 'simulated_error'}
        logger.error('data_fetch_failed', extra={'extra_fields': extra_fields})

        return jsonify({'error': 'data processing failed'}), 500

    business_operations_total.labels(
        operation='data_fetch',
        status='success'
    ).inc()

    # Generate sample data
    data = {
        'id': random.randint(1, 10000),
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'value': round(random.uniform(0, 100), 2),
        'status': 'processed',
        'processing_time_ms': round(processing_time * 1000, 2)
    }

    extra_fields = {
        'record_id': data['id'],
        'processing_ms': data['processing_time_ms']
    }
    logger.info('data_processed', extra={'extra_fields': extra_fields})

    return jsonify(data)

@app.route('/api/logs', methods=['POST'])
def trigger_logs():
    """Endpoint to trigger different log levels"""
    data = request.get_json()

    if not data:
        logger.error('invalid_request', extra={'extra_fields': {'error': 'no_json_body'}})
        return jsonify({'error': 'invalid request body'}), 400

    level = data.get('level', 'info')
    message = data.get('message', 'test_message')
    fields = data.get('fields', {})

    # Log based on level
    if level == 'info':
        logger.info(message, extra={'extra_fields': fields})
    elif level == 'error':
        logger.error(message, extra={'extra_fields': fields})
        business_operations_total.labels(
            operation='log_trigger',
            status='error'
        ).inc()
    elif level == 'warning':
        logger.warning(message, extra={'extra_fields': fields})
        business_operations_total.labels(
            operation='log_trigger',
            status='warning'
        ).inc()
    elif level == 'debug':
        logger.debug(message, extra={'extra_fields': fields})
    else:
        logger.info(message, extra={'extra_fields': fields})

    business_operations_total.labels(
        operation='log_trigger',
        status='success'
    ).inc()

    return jsonify({
        'status': 'logged',
        'level': level
    })

# Metrics endpoint
@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error('internal_server_error', extra={'extra_fields': {'error': str(error)}})
    return jsonify({'error': 'internal server error'}), 500

if __name__ == '__main__':
    logger.info('starting_application', extra={'extra_fields': {
        'version': '1.0.0',
        'port': 8080
    }})

    # Run Flask app
    app.run(host='0.0.0.0', port=8080, debug=False)
