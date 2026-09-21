# ==========================================
# 4 DATA BLOCKS (Meets '3+ data blocks' rule)
# ==========================================

# Data Block 1: Dynamic Availability Zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Data Block 2: Latest Ubuntu 22.04 LTS AMI dynamically
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Data Block 3: Dynamic AWS Account ID (For Tagging & Auditing)
data "aws_caller_identity" "current" {}

# Data Block 4: Current Region metadata
data "aws_region" "current" {}


# ==========================================
# CUSTOM NETWORK LAYER (No Default VPC!)
# ==========================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-vpc"
    Environment = terraform.workspace
    AccountID   = data.aws_caller_identity.current.account_id
    ManagedBy   = "Terraform"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-igw"
    Environment = terraform.workspace
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-subnet-${count.index + 1}"
    Environment = terraform.workspace
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-rt"
    Environment = terraform.workspace
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}


# ==========================================
# SECURITY LAYER
# ==========================================

resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-${terraform.workspace}-sg"
  description = "Allow HTTP and SSH"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP Inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-sg"
    Environment = terraform.workspace
  }
}


# ==========================================
# APPLICATION & EC2 LAYER
# ==========================================

# resource "aws_instance" "web_server" {
#   count                  = var.instance_count
#   ami                    = data.aws_ami.ubuntu.id
#   instance_type          = var.instance_type
#   subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
#   vpc_security_group_ids = [aws_security_group.web_sg.id]

#   # DYNAMIC FRONTEND INJECTION (Explained below)
#   user_data = <<-EOF
#               #!/bin/bash
#               apt-get update -y
#               apt-get install -y nginx
#               systemctl start nginx
#               systemctl enable nginx
              
#               # Terraform automatically injects the specific index.html content here:
#               cat <<'HTML' > /var/www/html/index.html
#               ${file("${path.module}/../frontend/${terraform.workspace}/index.html")}
#               HTML
#               EOF

#   tags = {
#     Name        = "${var.project_name}-${terraform.workspace}-instance-${count.index + 1}"
#     Environment = terraform.workspace
#     ManagedBy   = "Terraform"
#   }
# }

# resource "aws_instance" "web_server" {
#   count                  = var.instance_count
#   ami                    = data.aws_ami.ubuntu.id
#   instance_type          = var.instance_type
#   subnet_id              = aws_subnet.public[count.index % length(aws_subnet.public)].id
#   vpc_security_group_ids = [aws_security_group.web_sg.id]

#   # DYNAMIC USER DATA (Inserts unique server details onto the page)
#   user_data = <<-EOF
#               #!/bin/bash
#               apt-get update -y
#               apt-get install -y nginx curl
#               systemctl start nginx
#               systemctl enable nginx

#               # AWS Instance Metadata fetch (IMDSv2)
#               TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
#               INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
#               AZ_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

#               # Write HTML with unique server banner
#               cat <<'HTML' > /var/www/html/index.html
#               ${file("${path.module}/../frontend/${terraform.workspace}/index.html")}
#               HTML

#               # Inject live dynamic routing banner at the bottom of the page
#               sed -i "s|</div>|  <div style='margin-top: 20px; padding: 15px; background: #fff3e0; border: 2px solid #ff9800; border-radius: 8px;'><h3>⚡ Live Traffic Routing:</h3><p>Served by: <b>Instance #${count.index + 1} (${var.instance_type})</b></p><p>EC2 ID: <code>$INSTANCE_ID</code></p><p>Availability Zone: <b>$AZ_NAME</b></p></div></div>|g" /var/www/html/index.html
#               EOF

#   tags = {
#     Name        = "${var.project_name}-${terraform.workspace}-instance-${count.index + 1}"
#     Environment = terraform.workspace
#     ManagedBy   = "Terraform"
#   }
# }

resource "aws_instance" "web_server" {
  count                       = var.instance_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[count.index % length(aws_subnet.public)].id
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  user_data_replace_on_change = true # Naya code aate hi instance recreate karega

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y nginx curl
              systemctl start nginx
              systemctl enable nginx

              # Disable Nginx caching so every request hits fresh
              sed -i '/http {/a \    add_header Cache-Control "no-store, no-cache, must-revalidate, max-age=0";' /etc/nginx/nginx.conf
              systemctl restart nginx

              # Fetch Dynamic AWS Metadata
              TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
              AZ_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

              # Write complete interactive page
              cat <<HTML > /var/www/html/index.html
              <!DOCTYPE html>
              <html>
              <head>
                <title>PROD - Live Traffic Balancing</title>
                <meta http-equiv="refresh" content="4">
                <style>
                  body { font-family: Arial, sans-serif; text-align: center; margin-top: 50px; background-color: #f0f4f8; }
                  .card { border: 2px solid #1565c0; padding: 25px; display: inline-block; background: white; border-radius: 12px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); width: 450px; }
                  .badge { background-color: #1565c0; color: white; padding: 6px 14px; border-radius: 5px; font-weight: bold; }
                  .traffic-box { margin-top: 25px; padding: 15px; background: #fff8e1; border: 2px dashed #ffa000; border-radius: 8px; }
                  .server-highlight { font-size: 20px; color: #d84315; font-weight: bold; }
                </style>
              </head>
              <body>
                <div class="card">
                  <span class="badge">PRODUCTION LIVE</span>
                  <h2 style="color: #1565c0;">Customer-Facing Portal</h2>
                  <p>Target: <b>High Availability Multi-Instance (${var.instance_type})</b></p>
                  <p>Region: <b>${data.aws_region.current.name}</b></p>

                  <div class="traffic-box">
                    <h3> Live Traffic Routing</h3>
                    <p>Current Serving Node:</p>
                    <p class="server-highlight">Instance #${count.index + 1} of ${var.instance_count}</p>
                    <p>EC2 ID: <code>$INSTANCE_ID</code></p>
                    <p>Availability Zone: <b>$AZ_NAME</b></p>
                    <small style="color: gray;">Auto-refreshing every 4 seconds to test balancing...</small>
                  </div>
                </div>
              </body>
              </html>
              HTML
              EOF

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-instance-${count.index + 1}"
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
  }
}


# ==========================================
# ENTERPRISE LAYER: OPTIONAL ALB (PROD ONLY)
# ==========================================

# ALB Resource (Sirf tab banega jab enable_alb = true hoga)
resource "aws_lb" "prod_alb" {
  count              = var.enable_alb ? 1 : 0
  name               = "${var.project_name}-${terraform.workspace}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name        = "${var.project_name}-${terraform.workspace}-alb"
    Environment = terraform.workspace
    ManagedBy   = "Terraform"
  }
}

# Target Group (HTTP Port 80)
# resource "aws_lb_target_group" "prod_tg" {
#   count    = var.enable_alb ? 1 : 0
#   name     = "${var.project_name}-${terraform.workspace}-tg"
#   port     = 80
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.main.id

#   health_check {
#     path                = "/"
#     healthy_threshold   = 2
#     unhealthy_threshold = 3
#     timeout             = 5
#     interval            = 15
#   }
# }

# Target Group (HTTP Port 80)
resource "aws_lb_target_group" "prod_tg" {
  count                        = var.enable_alb ? 1 : 0
  name                         = "${var.project_name}-${terraform.workspace}-tg"
  port                         = 80
  protocol                     = "HTTP"
  vpc_id                       = aws_vpc.main.id
  load_balancing_algorithm_type = "round_robin"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }
}

# Attach EC2 instances to Target Group
resource "aws_lb_target_group_attachment" "attach_servers" {
  count            = var.enable_alb ? var.instance_count : 0
  target_group_arn = aws_lb_target_group.prod_tg[0].arn
  target_id        = aws_instance.web_server[count.index].id
  port             = 80
}

# Listener (Forwards port 80 traffic to Target Group)
resource "aws_lb_listener" "prod_listener" {
  count             = var.enable_alb ? 1 : 0
  load_balancer_arn = aws_lb.prod_alb[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prod_tg[0].arn
  }
}