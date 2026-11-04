#!/bin/sh

# Copy the HTML file to Nginx's directory
cp /app/public/* /usr/share/nginx/html/

# Keep the container running
tail -f /dev/null 