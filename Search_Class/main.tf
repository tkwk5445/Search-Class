# VPC 리소스 정의
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  instance_tenancy     = "default"
  tags = {
    Name = "dev-search-vpc"
  }
}

# Public 서브넷 정의
resource "aws_subnet" "public" {
  count             = length(var.public_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.public_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "dev-search-public-subnet${var.azs1[count.index]}"
  }
}
# Private 서브넷 정의
resource "aws_subnet" "private" {
  count             = length(var.private_subnet)
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.private_subnet[count.index]
  availability_zone = var.azs[count.index]
  tags = {
    Name = "dev-search-private-subnet${var.azs1[count.index]}"
  }
}

# Internet Gateway 리소스 정의
resource "aws_internet_gateway" "vpc_igw" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "dev-search-igw"
  }
}

# Elastic IP 리소스 정의
resource "aws_eip" "eip" {
  vpc        = true
  depends_on = [aws_internet_gateway.vpc_igw]
  tags = {
    Name = "dev-search-eip"
  }
  lifecycle {
    create_before_destroy = true
  }
}

# Public 서브넷에 대한 기본 라우팅 테이블 정의
resource "aws_default_route_table" "public_rt" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.vpc_igw.id
  }
  tags = {
    Name = "dev-search-public-rt"
  }
}

# Public 서브넷과 기본 라우팅 테이블의 연결 정의
resource "aws_route_table_association" "public_rta" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_default_route_table.public_rt.id
}

//Security Group
resource "aws_security_group" "web" {
  name        = "dev-search-web-sg"
  description = "accept all ports"
  vpc_id      = aws_vpc.vpc.id
  // 인바운드 규칙: 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dev-search-web-sg"
  }
}
resource "aws_security_group" "rds" {
  name   = "dev-search-rds-sg"
  vpc_id = aws_vpc.vpc.id
  // 인바운드 규칙 22, 3306 port
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  // 아웃바운드 규칙: 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" // 모든 프로토콜 허용
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "dev-search-rds-sg"
  }
}

// EC2 Instance (ubuntu)
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.image_id
  instance_type               = "t3.small"
  key_name                    = var.key
  vpc_security_group_ids      = [aws_security_group.web.id]
  subnet_id                   = aws_subnet.public[0].id
  availability_zone           = "ap-northeast-2a"
  associate_public_ip_address = true
  root_block_device {
    volume_size = 30
  }
  tags = {
    Name = "dev-search-web"
  }
}

// RDS subnet grouo
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private[0].id, aws_subnet.private[1].id]
}

// DB Instance (RDS)
resource "aws_db_instance" "rds" {
  identifier             = "dev-search-db"
  allocated_storage      = 30
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.small"
  username               = "brickmate"
  password               = "1q2w3e4r!"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
}