"""
Logging configuration for Sangeet AI Inference Daemon.
Configures structlog to output valid JSON lines strictly to standard error (stderr).
"""
import logging
import sys

import structlog


def configure_logging(verbose: bool = False) -> None:
    """
    Configures the global structlog processor chain to output JSON directly to stderr.
    Includes support for thread/context-local variables like request_id.
    """
    logging_level = logging.DEBUG if verbose else logging.INFO

    # Define standard processors to build the structured log event dictionary
    processors = [
        # Merge contextvars (like thread-local request_id) into the event dict
        structlog.contextvars.merge_contextvars,
        # Add severity level (info, error, debug)
        structlog.processors.add_log_level,
        # Add high-resolution ISO 8601 timestamp
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        # Render stack traces nicely if present
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        # Render final output as single-line JSON
        structlog.processors.JSONRenderer()
    ]

    structlog.configure(
        processors=processors,
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(sys.stderr),
        wrapper_class=structlog.make_filtering_bound_logger(logging_level),
        cache_logger_on_first_use=True,
    )
