# Documentation Index

## Overview

All documentation is organized in the `/docs/` directory for better organization and discoverability.

## Core Documentation

### System Architecture
- **[README.md](README.md)** - Project overview and setup
- **[docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md)** - ServiceContainer and dependency injection ✅ NEW
- **[docs/EVENTBUS_SYSTEM.md](docs/EVENTBUS_SYSTEM.md)** - Event-driven pub/sub communication ✅ NEW
- **[docs/REMOTE_ARCHITECTURE.md](docs/REMOTE_ARCHITECTURE.md)** - RFRegistry and RemoteManager system ✅ NEW
- **[docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md)** - API documentation index ✅ UPDATED
  - **[docs/API_REMOTE_FUNCTIONS.md](docs/API_REMOTE_FUNCTIONS.md)** - RemoteFunction reference (46+ functions)
  - **[docs/API_REMOTE_EVENTS.md](docs/API_REMOTE_EVENTS.md)** - RemoteEvent reference (via EventBus)
  - **[docs/API_BEST_PRACTICES.md](docs/API_BEST_PRACTICES.md)** - Best practices, examples, testing
- **[docs/ARCHITECTURE_REFACTOR_Q1_2025.md](docs/ARCHITECTURE_REFACTOR_Q1_2025.md)** - Q1 2025 refactor implementation ✅ COMPLETED
- **[docs/MASTER_IMPLEMENTATION_ROADMAP.md](docs/MASTER_IMPLEMENTATION_ROADMAP.md)** - Development roadmap
- **[docs/PLANNING_INDEX.md](docs/PLANNING_INDEX.md)** - Planning documents overview
- **[docs/CURRENT_IMPLEMENTATION_PLAN.md](docs/CURRENT_IMPLEMENTATION_PLAN.md)** - Current sprint/implementation status

### Core Systems Documentation

#### UI System ✅
- **[docs/UI_SYSTEM.md](docs/UI_SYSTEM.md)** - Complete UI system architecture
- **[docs/UI_COMPONENT_GUIDE.md](docs/UI_COMPONENT_GUIDE.md)** - Step-by-step component creation guide
- **[docs/UI_COMPLETE_DESIGN.md](docs/UI_COMPLETE_DESIGN.md)** - Original UI design document

#### Account & Data System ✅
- **[docs/ACCOUNT_SYSTEM.md](docs/ACCOUNT_SYSTEM.md)** - Account, profile, and data persistence
- **[docs/PLAYTIME_TRACKING_SYSTEM.md](docs/PLAYTIME_TRACKING_SYSTEM.md)** - Session and lifetime playtime tracking

#### Material System ✅
- **[docs/MATERIAL_SYSTEM_REFERENCE.md](docs/MATERIAL_SYSTEM_REFERENCE.md)** - Quick reference for material system
- **[docs/ADDING_NEW_MATERIALS.md](docs/ADDING_NEW_MATERIALS.md)** - Complete guide for adding terrain materials

#### Sound System ✅
- **[docs/SOUND_INTEGRATION_REVIEW.md](docs/SOUND_INTEGRATION_REVIEW.md)** - Sound system architecture
- **[docs/AMBIENT_ZONE_DOCUMENTATION.md](docs/AMBIENT_ZONE_DOCUMENTATION.md)** - Ambient sound zone system

#### Animation & Visual Systems ✅
- **[docs/CLOTH_SYSTEM.md](docs/CLOTH_SYSTEM.md)** - Cloth simulation with bone deformation
- **[docs/SKINNED_MESH_ANIMATION_GUIDE.md](docs/SKINNED_MESH_ANIMATION_GUIDE.md)** - Skinned mesh animation guide

### Game Systems Documentation

#### Loot & Rewards
- **[docs/DROP_TABLE_SYSTEM.md](docs/DROP_TABLE_SYSTEM.md)** - Loot and drop mechanics
- **[docs/UI_AFK_REWARDS_DESIGN.md](docs/UI_AFK_REWARDS_DESIGN.md)** - AFK reward system design

#### World & Environment
- **[docs/MAP_SYSTEM_DESIGN.md](docs/MAP_SYSTEM_DESIGN.md)** - World generation and mapping
- **[docs/SPAWN_AND_DECORATION_PLAN.md](docs/SPAWN_AND_DECORATION_PLAN.md)** - Spawn system design

#### Game Mechanics
- **[docs/DIG_SERVICE.md](docs/DIG_SERVICE.md)** - Mining/digging mechanics and boundary validation ✅
- **[docs/EXTRACTION_QUOTA_SYSTEM.md](docs/EXTRACTION_QUOTA_SYSTEM.md)** - Quota mechanics

## Documentation Status

### Fully Documented ✅
- Service Architecture (ServiceContainer, dependency injection, lifecycle management)
- Remote Architecture (RFRegistry, RemoteManager, schema validation, rate limiting)
- EventBus System (Pub/sub pattern, event flow, middleware support)
- API System (Complete RemoteFunction/RemoteEvent reference with schemas)
- UI System (Architecture, Components, Creation Guide)
- Account & Profile System (DataService, SessionService, AccountDataProvider)
- Material System (Definitions, Keys, Adding Materials)
- Sound System (Manager, Zones, Integration)
- Cloth Simulation System (Bone deformation, server-client replication)
- Playtime Tracking
- Drop/Loot System (Drop tables, rarity, modifiers)
- Dig Service (Mining mechanics, boundary validation, rate limiting)

### Partially Documented ⚠️
- Map System (design document exists, not implemented)
- Spawn System (design document exists)
- Extraction/Quota System (design document exists)
- AFK Rewards (design document exists)

### Needs Documentation ❌
- Movement System (double jump, terrain-based speed, gravity)
- Grid Service (voxel terrain management, chunk system)
- Inventory Service (item management, stacking)
- Upgrade Service (player progression, tool upgrades)
- FloatingIslandService (special world features)
- CharacterStateManager (state management system)
- Development Setup Guide
- Testing Procedures
- Debugging Guide

## Quick Reference

### For New Developers
1. Start with [README.md](README.md)
2. Understand [docs/SERVICE_ARCHITECTURE.md](docs/SERVICE_ARCHITECTURE.md) - How services work
3. Learn [docs/EVENTBUS_SYSTEM.md](docs/EVENTBUS_SYSTEM.md) - Event communication
4. Study [docs/REMOTE_ARCHITECTURE.md](docs/REMOTE_ARCHITECTURE.md) - Client-server communication
5. Review [docs/UI_COMPONENT_GUIDE.md](docs/UI_COMPONENT_GUIDE.md) for UI work
6. Check [docs/MATERIAL_SYSTEM_REFERENCE.md](docs/MATERIAL_SYSTEM_REFERENCE.md) for material work

### For UI Development
- [docs/UI_SYSTEM.md](docs/UI_SYSTEM.md) - Architecture overview
- [docs/UI_COMPONENT_GUIDE.md](docs/UI_COMPONENT_GUIDE.md) - Creating components
- [docs/ACCOUNT_SYSTEM.md](docs/ACCOUNT_SYSTEM.md) - Data providers

### For Game Systems
- [docs/MATERIAL_SYSTEM_REFERENCE.md](docs/MATERIAL_SYSTEM_REFERENCE.md) - Materials
- [docs/SOUND_INTEGRATION_REVIEW.md](docs/SOUND_INTEGRATION_REVIEW.md) - Sounds
- [docs/DROP_TABLE_SYSTEM.md](docs/DROP_TABLE_SYSTEM.md) - Loot

## Documentation Standards

### File Organization
All documentation files are stored in the `/docs/` directory with descriptive names:
- System docs: `SYSTEM_NAME.md` or `SYSTEM_NAME_DOCUMENTATION.md`
- Design docs: `FEATURE_NAME_DESIGN.md`
- Guides: `GUIDE_NAME.md` or `SYSTEM_NAME_GUIDE.md`
- References: `SYSTEM_NAME_REFERENCE.md`

### Structure Template
```markdown
# System Name

## Overview
Brief description of what the system does

## Quick Start
Minimal steps to use the system

## Architecture
How the system works internally

## API Reference
All public methods and properties

## Configuration
Adjustable settings and where to find them

## Examples
Common use cases with code

## Troubleshooting
Common issues and solutions
```

## Recent Updates (September 2025)

### September 9, 2025
- ✅ Created Service Architecture documentation (ServiceContainer, DI, lifecycle)
- ✅ Created EventBus System documentation (pub/sub, middleware, event flow)
- ✅ Created Remote Architecture documentation (RFRegistry, RemoteManager, validation)
- ✅ Updated API Documentation to reflect new RFRegistry pattern
- ✅ Documented Q1 2025 refactor completion in ARCHITECTURE_REFACTOR_Q1_2025.md

### September 3, 2025
- ✅ Created comprehensive Cloth System documentation
- ✅ Updated Skinned Mesh Animation Guide with bone replication discoveries
- ✅ Updated implementation plans with current project status
- ✅ Corrected remote counts (46+ RF via RFRegistry, events via EventBus)
- ✅ Added timeline reality check to implementation plan

## Next Documentation Priorities

1. **Movement System** - Players need to understand movement mechanics
2. **Development Setup Guide** - For new team members
3. **Individual Service Documentation** - GridService, InventoryService, UpgradeService
4. **Testing Guide** - How to test features with new architecture
5. **Debugging Guide** - Common issues and solutions with new patterns
6. **FloatingIslandService** - Document special world features
7. **CharacterStateManager** - State management patterns