FROM python:3.14-slim

# Copy uv from the official image
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# 1. Disable bytecode writing (faster startup, cleaner image)
# 2. Unbuffered output (logs show up immediately)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Create a non-root user
RUN useradd -u 1000 -m appuser

# Grant appuser ownership of the /app directory
RUN chown -R appuser:appuser /app

# Copy all application code into the image
COPY --chown=appuser:appuser . .

# Switch to the non-root user for subsequent operations
USER appuser

# Install all dependencies and the project itself
RUN uv sync --frozen --no-cache

# Add the virtual environment to the PATH
ENV PATH="/app/.venv/bin:$PATH"

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]