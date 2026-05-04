# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the **microdevops-formula** repository - a comprehensive SaltStack formula collection for managing infrastructure and applications. It's designed to handle everything from basic system configuration to complex application deployments across hundreds of servers.

## Key Architecture Components

### Formula Structure
- **State files (.sls)**: Main configuration and deployment logic
- **Pillar examples**: Configuration templates for each service/component
- **Jinja templates**: Dynamic configuration generation
- **Files directory**: Static configuration files, scripts, and assets

### Core Service Categories
- **Infrastructure**: nginx, php-fpm, docker-ce, ufw_simple (firewall), bootstrap (system setup)
- **Applications**: app (web app deployment), wordpress, gitlab, nextcloud, sentry
- **Monitoring**: netdata, prometheus, grafana, alertmanager, cmd_check_alert
- **Databases**: percona (MySQL), postgresql, mongodb, redis
- **Security**: authentik, keycloak, vault, wazuh
- **Backup**: rsnapshot_backup with sysadmws-utils integration
- **Networking**: keepalived, haproxy, consul

### Application Deployment System
The `app/` formula provides a sophisticated deployment system supporting:
- **PHP-FPM applications** with nginx integration
- **Python applications** with various WSGI servers
- **Static sites** with nginx optimization
- **WordPress** deployments with specialized configurations
- **Docker-based applications**

Key files:
- `app/init.sls`: Main deployment orchestration
- `app/deploy.sls`: Core deployment logic
- `app/_nginx.sls`: Nginx vhost configuration
- `app/_user_and_source.sls`: User setup and source code management

## Common Salt Commands

### Basic Operations
```bash
# Apply a specific state
salt 'minion-id' state.apply nginx

# Apply with specific pillar data
salt 'minion-id' state.apply app.php-fpm pillar='{"nginx_reload": true}'

# Test configuration
salt 'minion-id' state.apply test.git_commit
```

### Application Deployment
```bash
# Deploy PHP-FPM application
salt 'minion-id' state.apply app.php-fpm

# Deploy static application
salt 'minion-id' state.apply app.static

# Deploy Python application
salt 'minion-id' state.apply app.python
```

### System Management
```bash
# Bootstrap system (initial setup)
salt 'minion-id' state.apply bootstrap

# Update firewall rules
salt 'minion-id' state.apply ufw_simple

# Configure monitoring
salt 'minion-id' state.apply netdata
salt 'minion-id' state.apply cmd_check_alert
```

### Backup Operations
```bash
# Update backup configuration
salt 'minion-id' state.apply rsnapshot_backup.update_config

# Check backup coverage
salt 'minion-id' state.apply rsnapshot_backup.check_coverage

# Run backup sync
salt 'minion-id' cmd.run '/opt/sysadmws/rsnapshot_backup/rsnapshot_backup_sync_monthly_weekly_daily_check_backup.sh'
```

## Configuration Management

### Pillar Structure
- Each service has a `pillar.example` file showing configuration options
- Main pillar reference at `/pillar.example` points to individual service examples
- Ready-to-use pillar templates in `pillar/` directory with common configurations

### SSL/TLS with ACME
The formula integrates with acme.sh for automated SSL certificate management:
- Webroot validation for Let's Encrypt certificates
- Automatic nginx configuration for HTTPS redirects
- Integration with various DNS providers (CloudFlare, GoDaddy, etc.)

### UFW Simple Firewall
Advanced firewall management system (`ufw_simple/`) that:
- Extends UFW with NAT and raw iptables rules
- Manages firewall rules across hundreds of servers
- Includes predefined rule sets for common scenarios
- Supports Docker integration and complex networking

### Monitoring Integration
Comprehensive monitoring setup:
- **Netdata**: Real-time system monitoring
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **cmd_check_alert**: Custom health checks with alert integration

## Development Workflow

### Making Changes
1. Modify the appropriate `.sls` state file
2. Update corresponding `pillar.example` if configuration changes
3. Test changes on development minions first
4. Use `state.apply` to deploy changes

### Testing
- Use `salt-call --local state.apply` for local testing
- The `test/` directory contains validation states
- Bootstrap testing available via `bootstrap/test.sls`

### Scripts and Automation
- `scripts/ci_sudo/`: Scripts for running Salt states via CI/CD
- `scripts/salt-ssh/`: Salt-SSH specific scripts
- Integration with GitLab CI for automated deployments

## File Organization

- **Top-level directories**: Each represents a service or component
- **init.sls**: Main state file for each service
- **pillar.example**: Configuration template
- **files/**: Static files, templates, and scripts
- **defaults.yaml**: Default variables for complex services
- **map.jinja**: OS-specific variable mapping where needed

## Important Notes

- This formula is designed for production environments managing hundreds of servers
- Many services are configured to work together (nginx + php-fpm + app deployment)
- The backup system (`rsnapshot_backup`) is tightly integrated with `sysadmws-utils`
- Firewall rules (`ufw_simple`) are designed for complex multi-server environments
- SSL certificates are automated via acme.sh integration