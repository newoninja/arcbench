"""
Agent Registry — 10 specialized AI build agents for ArcBench Spark Ideas.

Each agent has:
  - slug: URL-safe identifier
  - name: Human-readable display name
  - soul_path: Path to SOUL.md personality/instruction file
  - tools: List of MCP tools/CLI tools the agent can invoke
  - auto_grok_review: Whether to auto-schedule Grok review after COMPLETE
  - chip_labels: Which quick-chip labels map to this agent
  - description: One-line summary for classification
"""

from __future__ import annotations

import re
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

logger = logging.getLogger("arcbench.agents.registry")

SOULS_DIR = Path(__file__).parent / "souls"


@dataclass(frozen=True)
class AgentSpec:
    slug: str
    name: str
    soul_path: Path
    tools: list[str]
    auto_grok_review: bool = True
    chip_labels: list[str] = field(default_factory=list)
    description: str = ""
    working_dir_suffix: str = ""  # Appended to ~/arcbench-builds/<slug>/
    post_approve_chain: str | None = None  # Optional: slug of agent to chain after approval


# ─── The 10 Agents ───

AGENT_REGISTRY: dict[str, AgentSpec] = {}


def _register(spec: AgentSpec):
    AGENT_REGISTRY[spec.slug] = spec
    return spec


_register(AgentSpec(
    slug="test-site-creator",
    name="TestSiteCreator",
    soul_path=SOULS_DIR / "test_site_creator.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch"],
    auto_grok_review=True,
    chip_labels=["Test Landing Page"],
    description="Builds complete test/demo landing pages with HTML, CSS, JS, and local preview server.",
))

_register(AgentSpec(
    slug="client-proposal-maker",
    name="ClientProposalMaker",
    soul_path=SOULS_DIR / "client_proposal_maker.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "WebFetch"],
    auto_grok_review=True,
    chip_labels=["Client Proposal"],
    description="Generates polished client proposals with scope, timeline, budget, and deliverables.",
))

_register(AgentSpec(
    slug="marketing-funnel-builder",
    name="MarketingFunnelBuilder",
    soul_path=SOULS_DIR / "marketing_funnel_builder.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch"],
    auto_grok_review=True,
    chip_labels=["Marketing Funnel"],
    description="Creates multi-step marketing funnels: landing pages, email sequences, opt-in forms, analytics.",
))

_register(AgentSpec(
    slug="ai-dashboard-generator",
    name="AIDashboardGenerator",
    soul_path=SOULS_DIR / "ai_dashboard_generator.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch"],
    auto_grok_review=True,
    chip_labels=["AI Dashboard"],
    description="Generates data dashboards with charts, KPIs, and real-time feeds using modern frontend stacks.",
))

_register(AgentSpec(
    slug="content-package-creator",
    name="ContentPackageCreator",
    soul_path=SOULS_DIR / "content_package_creator.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob"],
    auto_grok_review=True,
    chip_labels=[],
    description="Creates content packages: blog posts, social media kits, copy decks, and brand guides.",
))

_register(AgentSpec(
    slug="landing-page-optimizer",
    name="LandingPageOptimizer",
    soul_path=SOULS_DIR / "landing_page_optimizer.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch"],
    auto_grok_review=True,
    chip_labels=[],
    description="Audits and optimizes existing landing pages for conversion, speed, SEO, and accessibility.",
))

_register(AgentSpec(
    slug="invoice-generator",
    name="InvoiceGenerator",
    soul_path=SOULS_DIR / "invoice_generator.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob"],
    auto_grok_review=True,
    chip_labels=[],
    description="Generates professional invoices and billing documents in PDF/HTML with line items and branding.",
))

_register(AgentSpec(
    slug="email-sequence-builder",
    name="EmailSequenceBuilder",
    soul_path=SOULS_DIR / "email_sequence_builder.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob"],
    auto_grok_review=True,
    chip_labels=[],
    description="Creates multi-email drip sequences: welcome series, onboarding flows, re-engagement campaigns.",
))

_register(AgentSpec(
    slug="product-roadmap-creator",
    name="ProductRoadmapCreator",
    soul_path=SOULS_DIR / "product_roadmap_creator.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob"],
    auto_grok_review=True,
    chip_labels=[],
    description="Builds product roadmaps with milestones, dependencies, resource allocation, and timeline visuals.",
))

_register(AgentSpec(
    slug="custom-code-agent",
    name="CustomCodeAgent",
    soul_path=SOULS_DIR / "custom_code_agent.md",
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", "WebFetch"],
    auto_grok_review=True,
    chip_labels=["Custom Idea"],
    description="General-purpose code agent. Interprets freeform ideas and builds whatever the user describes.",
))


# ─── Lookup helpers ───

def get_agent(slug: str) -> Optional[AgentSpec]:
    """Get an agent spec by slug."""
    return AGENT_REGISTRY.get(slug)


def agent_for_chip(chip_label: str) -> Optional[AgentSpec]:
    """Find the agent mapped to a quick-chip label."""
    for spec in AGENT_REGISTRY.values():
        if chip_label in spec.chip_labels:
            return spec
    return None


def classify_agent(idea_text: str, chip_label: Optional[str] = None) -> AgentSpec:
    """
    Classify which agent should handle a spark idea.

    Priority:
      1. Exact chip_label match (user selected a chip)
      2. Keyword matching against agent descriptions
      3. Fallback to CustomCodeAgent
    """
    # 1. Chip label match
    if chip_label:
        agent = agent_for_chip(chip_label)
        if agent:
            logger.info(f"Classified by chip '{chip_label}' -> {agent.slug}")
            return agent

    # 2. Keyword scoring
    text_lower = idea_text.lower()
    best_score = 0
    best_agent: Optional[AgentSpec] = None

    _keyword_map = {
        "test-site-creator":      ["landing page", "test site", "demo page", "test page", "website", "html page"],
        "client-proposal-maker":  ["proposal", "client", "scope", "deliverable", "quote", "bid", "pitch"],
        "marketing-funnel-builder": ["funnel", "marketing", "lead", "opt-in", "conversion", "campaign"],
        "ai-dashboard-generator": ["dashboard", "chart", "kpi", "analytics", "metrics", "visualization", "data"],
        "content-package-creator": ["content", "blog", "social media", "copy", "brand guide", "content pack"],
        "landing-page-optimizer": ["optimize", "audit", "seo", "speed", "conversion rate", "a/b test"],
        "invoice-generator":     ["invoice", "billing", "receipt", "payment", "line item"],
        "email-sequence-builder": ["email", "drip", "sequence", "newsletter", "onboarding", "welcome series"],
        "product-roadmap-creator": ["roadmap", "milestone", "sprint", "timeline", "product plan", "release"],
    }

    for slug, keywords in _keyword_map.items():
        score = sum(1 for kw in keywords if kw in text_lower)
        if score > best_score:
            best_score = score
            best_agent = AGENT_REGISTRY.get(slug)

    if best_agent and best_score >= 1:
        logger.info(f"Classified by keywords (score={best_score}) -> {best_agent.slug}")
        return best_agent

    # 3. Fallback
    fallback = AGENT_REGISTRY["custom-code-agent"]
    logger.info(f"No keyword match, falling back to {fallback.slug}")
    return fallback
