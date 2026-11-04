
find /usr/src/app/assets/exams -type d -path "*/*/scripts" | while read scripts_dir; do \
    exam_dir=$(dirname "$scripts_dir"); \
    cd "$exam_dir"; \
    echo "Creating tar archive of scripts in $exam_dir"; \
    tar -czf assets.tar.gz scripts/; \
    rm -rf scripts/; \
    cd - > /dev/null; \
done

echo "Assets created"

# Start the application
node src/app.js