# Civilisation-game-

A civilisation idle game (Godot 4.7.2): grow a tribe from wood and food up through stone, clay, copper, bronze, iron, coal, steel, oil, electricity, silicon, uranium, antimatter and dark matter. Later: crafted items with synergies and real-time top-down conquest.

## Layout

- `scripts/data/game_data.gd`: all resources, discoveries, jobs, buildings and upgrades (edit numbers here)
- `scripts/autoload/game.gd`: simulation (jobs, food, spoilage, population, modifiers, offline progress)
- `scripts/autoload/save_manager.gd`: autosave every 30s and on quit, to `user://save.json`
- `scripts/ui/main.gd`: placeholder UI built in code
- `assets/`: art, named literally (`Wood.png`, `Stone House.png`, `Background.png`)

## Tests

```
godot --headless --path . -s tests/test_economy.gd
```
