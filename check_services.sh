#!/bin/bash

# Check if MySQL is running
check_mysql() {
    if systemctl is-active --quiet mysqld || systemctl is-active --quiet mariadb; then
        echo "MySQL is running."
        return 0
    else
        echo "MySQL is NOT running!"
        return 1
    fi
}

# Check if Apache HTTP Server (httpd) is running
check_httpd() {
    if systemctl is-active --quiet httpd || systemctl is-active --quiet apache2; then
        echo "Apache HTTP Server is running."
        return 0
    else
        echo "Apache HTTP Server is NOT running!"
        return 1
    fi
}

# Main function
main() {
    local mysql_failed=0
    local httpd_failed=0
    
    # Check MySQL
    if ! check_mysql; then
        mysql_failed=1
    fi
    
    # Check Apache HTTP Server
    if ! check_httpd; then
        httpd_failed=1
    fi
    
    # Exit with appropriate status
    if [ $mysql_failed -eq 1 ] || [ $httpd_failed -eq 1 ]; then
        echo "At least one critical service is down!"
        exit 1
    else
        echo "All services are running normally."
        exit 0
    fi
}

# Execute main function
main
