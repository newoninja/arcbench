"""ArcBench Agent Registry — 10 specialized AI build agents with auto Grok review."""

from agents.registry import AGENT_REGISTRY, get_agent, classify_agent
from agents.dispatcher import dispatch_spark

__all__ = ["AGENT_REGISTRY", "get_agent", "classify_agent", "dispatch_spark"]
