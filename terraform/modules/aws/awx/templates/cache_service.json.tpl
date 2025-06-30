[
    {
        "name": "memcached",
        "image": "public.ecr.aws/docker/library/memcached:1.6-alpine",
        "essential": true,
        "memory": 512,
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "${log_group}",
                "awslogs-region": "${aws_region}",
                "awslogs-stream-prefix": "${cluster_name}-cache"
            }
        },
        "portMappings": [
            {
                "containerPort": 11211,
                "hostPort": 11211,
                "protocol": "tcp"
            }
        ],
        "command": [
            "memcached",
            "-m", "256",
            "-I", "5m",
            "-v"
        ],
        "healthCheck": {
            "command": [
                "CMD-SHELL",
                "timeout 5 bash -c '</dev/tcp/localhost/11211' || exit 1"
            ],
            "interval": 30,
            "timeout": 5,
            "retries": 3,
            "startPeriod": 10
        }
    }
] 