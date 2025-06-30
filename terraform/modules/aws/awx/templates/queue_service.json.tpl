[
    {
        "name": "rabbitmq",
        "image": "ansible/awx_rabbitmq:3.7.4",
        "essential": true,
        "memory": 1024,
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "${log_group}",
                "awslogs-region": "${aws_region}",
                "awslogs-stream-prefix": "${cluster_name}-queue"
            }
        },
        "portMappings": [
            {
                "containerPort": 5672,
                "hostPort": 5672,
                "protocol": "tcp"
            }
        ],
        "environment": [
            {
                "name": "RABBITMQ_DEFAULT_VHOST",
                "value": "awx"
            },
            {
                "name": "RABBITMQ_DEFAULT_USER",
                "value": "guest"
            },
            {
                "name": "RABBITMQ_DEFAULT_PASS",
                "value": "awxpass"
            },
            {
                "name": "RABBITMQ_ERLANG_COOKIE",
                "value": "cookiemonster"
            }
        ]
    }
] 