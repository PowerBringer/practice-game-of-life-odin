package main

import "core:fmt"
import "core:math"
import "core:strings"
import rl "vendor:raylib"

TITLE :: "[Conway's Game of Life]"
WIDTH : i32: 1600
HEIGHT : i32 : 900
FPS :: -1
GENERATION_LIFETIME_MS : f32 : 0.05  // ~20 generations per second
EXIT_KEY :: rl.KeyboardKey.ESCAPE
DEFAULT_FONT_SIZE : i32 : 20
DEFAULT_TEXT_COLOR :: rl.DARKBROWN
DEFAULT_TEXT_SHADOW_COLOR :: rl.BROWN
BG_COLOR : rl.Color : {221, 186, 141, 255}  // Little bit brighter than rl.BEIGE

MAP_SIZE :: 220
CELL_SIZE : f32 : 8
END_CELLS_POS :: MAP_SIZE * CELL_SIZE
DRAW_TOOL_PANEL_W : f32 : 96
DRAW_TOOL_PANEL_H : f32 : 32

UI :: struct {
    generation_num :        u64,
    selected_draw_type :    u8,

    fps_text :              cstring,
    fps_text_pos :          [2]i32,

    generation_text :       cstring,
    generation_text_pos :   [2]i32,

    paused_text :           cstring,
    pause_text_pos :        [2]i32,

    pencil_text :           cstring,
    pencil_text_pos :       [2]i32,
    pencil_rec :            rl.Rectangle,  // selected_draw_type = 1

    glider_text :           cstring,
    glider_text_pos :       [2]i32,
    glider_rec :            rl.Rectangle,  // selected_draw_type = 2
}

main :: proc() {
    using rl

    camera : Camera2D = { zoom = 1.0 }

    cell_recs : [MAP_SIZE][MAP_SIZE]Rectangle
    cells : [MAP_SIZE][MAP_SIZE]u8
    cells_bufer : [MAP_SIZE][MAP_SIZE]u8
    cell_colors : [2]Color = { BEIGE, DARKBROWN } // 0 -> cell is "dead", 1 -> "alive"

    is_in_greetings_screen := true
    is_paused := true
    process_one_generation := false
    curr_gen_lifetime : f32 = 0

    InitWindow(i32(WIDTH), i32(HEIGHT), TITLE)
    SetTargetFPS(FPS)

    // Pre-calculate UI positions and rectangles
    ui : UI
    ui.fps_text_pos = {WIDTH - 100, 2}
    ui.paused_text = "PAUSED"
    text_width := rl.MeasureText(ui.paused_text, DEFAULT_FONT_SIZE)
    ui.generation_num = 0
    ui.selected_draw_type = 1  // draw individual cells by default
    ui.generation_text_pos = {2, 2}
    ui.pause_text_pos = {(i32(WIDTH) - text_width) / 2, 2}
    ui.pencil_text = "PENCIL"
    pencil_text_width := MeasureText(ui.pencil_text, DEFAULT_FONT_SIZE)
    ui.pencil_rec = {f32(ui.pause_text_pos.x + text_width) + 20, 2, DRAW_TOOL_PANEL_W, DRAW_TOOL_PANEL_H}
    ui.pencil_text_pos = {
        i32(ui.pencil_rec.x) + (i32(ui.pencil_rec.width) - pencil_text_width) / 2, 
        i32(ui.pencil_rec.y) + (i32(ui.pencil_rec.height) - DEFAULT_FONT_SIZE) / 2,
    }
    ui.glider_text = "GLIDER"
    glider_text_width := MeasureText(ui.glider_text, DEFAULT_FONT_SIZE)
    ui.glider_rec = {ui.pencil_rec.x + DRAW_TOOL_PANEL_W + 5, 2, DRAW_TOOL_PANEL_W, DRAW_TOOL_PANEL_H}
    ui.glider_text_pos = {
        i32(ui.glider_rec.x) + (i32(ui.glider_rec.width) - glider_text_width) / 2, 
        i32(ui.glider_rec.y) + (i32(ui.glider_rec.height) - DEFAULT_FONT_SIZE) / 2,
    }

    // Pre-calculate cell rectangles for drawing once
    for y in 0..<MAP_SIZE {
        for x in 0..<MAP_SIZE {
            cell_recs[y][x] = {f32(x) * CELL_SIZE, f32(y) * CELL_SIZE, CELL_SIZE, CELL_SIZE}
        }
    }

    // Place starting "Glider" figure, which will move in bottom-right direction
    place_glider(&cells, 4, 4)

    // Greetings screen
    SetExitKey(KeyboardKey.KEY_NULL) // We don't want to close app window before starting simulation
    for is_in_greetings_screen {
        update_greetings_screen(&is_in_greetings_screen)
        if !is_in_greetings_screen { break }
        draw_greetings_screen()
    }
    SetExitKey(EXIT_KEY)

    // Main loop
    for !WindowShouldClose() {
        out_of_grid := false
        curr_gen_lifetime += GetFrameTime()
        mouse_position : Vector2 = GetMousePosition()
        mouse_dt : Vector2 = GetMouseDelta()
        hovered_cell_index : [2]int = {-1, -1}

        // Change camera position
        if IsMouseButtonDown(MouseButton.MIDDLE) {
            camera.target -= mouse_dt
        }
        local_mouse_pos := mouse_position + camera.target
        // Get hovered cell index
        if local_mouse_pos.x > 0 && local_mouse_pos.x < END_CELLS_POS {
            hovered_cell_index.x = int(math.floor(local_mouse_pos.x / CELL_SIZE))
        }
        if local_mouse_pos.y > 0 && local_mouse_pos.y < END_CELLS_POS {
            hovered_cell_index.y = int(math.floor(local_mouse_pos.y / CELL_SIZE))
        }

        if hovered_cell_index.x == -1 || hovered_cell_index.y == -1 {
            out_of_grid = true
        }

        if IsKeyPressed(KeyboardKey.SPACE) || IsKeyPressed(KeyboardKey.P) {
            is_paused = !is_paused
        }
        if IsKeyPressed(KeyboardKey.N) {
            process_one_generation = !process_one_generation
        }
        // Restart
        if IsKeyPressed(KeyboardKey.R) {
            restart(&cells, &is_paused)
        }
        // Process UI
        update_ui(&ui)
        // Set cell state to alive at mouse position ("Draw" cell)
        if IsMouseButtonDown(MouseButton.LEFT) && ui.selected_draw_type == 1 && !out_of_grid {
            cells[hovered_cell_index.y][hovered_cell_index.x] = 1
        }
        else if IsMouseButtonPressed(MouseButton.LEFT) && ui.selected_draw_type == 2 && !out_of_grid {  // Place "Glider" figure
            place_glider(&cells, hovered_cell_index.x, hovered_cell_index.y)
        }

        // Update generation state
        if (!is_paused || process_one_generation) && curr_gen_lifetime >= GENERATION_LIFETIME_MS {
            process_next_generation(&cells, &cells_bufer)
            cells = cells_bufer
            cells_bufer = {}
            process_one_generation = false
            ui.generation_num += 1
            curr_gen_lifetime = 0.0
        }

        BeginDrawing()
        ClearBackground(BG_COLOR)

        // Draw current generation
        BeginMode2D(camera)
        for y in 0..<MAP_SIZE {
            for x in 0..<MAP_SIZE {
                DrawRectangleRec(cell_recs[y][x], cell_colors[cells[y][x]])
            }
        }
        EndMode2D()

        // Draw UI
        draw_ui(ui, is_paused)
        EndDrawing()

        free_all(context.temp_allocator)
    }
    CloseWindow()
}

update_ui :: #force_inline proc(ui: ^UI) {
    if rl.IsKeyPressed(rl.KeyboardKey.ONE) {
        ui.selected_draw_type = 1
    }
    if rl.IsKeyPressed(rl.KeyboardKey.TWO) {
        ui.selected_draw_type = 2
    }
    ui.generation_text = fmt.ctprintf("GENERATION # {}", ui.generation_num)
    ui.fps_text = fmt.ctprintf("FPS {}", rl.GetFPS())
}

draw_ui :: #force_inline proc(ui: UI, is_paused: bool) {
    draw_text_with_shadow(ui.generation_text, 0, 0)

    rl.DrawRectangleRec(ui.pencil_rec, rl.BROWN)
    rl.DrawRectangleLinesEx(ui.pencil_rec, 3, rl.DARKBROWN)
    draw_text_with_shadow(ui.pencil_text, ui.pencil_text_pos.x, ui.pencil_text_pos.y)
    rl.DrawRectangleRec(ui.glider_rec, rl.BROWN)
    rl.DrawRectangleLinesEx(ui.glider_rec, 3, rl.DARKBROWN)
    draw_text_with_shadow(ui.glider_text, ui.glider_text_pos.x, ui.glider_text_pos.y)

    switch ui.selected_draw_type {
        case 1: rl.DrawRectangleLinesEx(ui.pencil_rec, 2, rl.GOLD)
        case 2: rl.DrawRectangleLinesEx(ui.glider_rec, 2, rl.GOLD)
        case 0, 3..=255: 
    }

    if is_paused {
        draw_text_with_shadow(ui.paused_text, ui.pause_text_pos.x, ui.pause_text_pos.y)
    }

    draw_text_with_shadow(ui.fps_text, ui.fps_text_pos.x, ui.fps_text_pos.y)
}

place_glider :: proc(cells : ^[MAP_SIZE][MAP_SIZE]u8, center_x, center_y: int) {
    if center_x == MAP_SIZE - 1 { return }
    else if center_y == 0 || center_y == MAP_SIZE - 1 { return }
    cells[center_y][center_x] = 1
    cells[center_y + 1][center_x + 1] = 1
    cells[center_y - 1][center_x + 2] = 1
    cells[center_y][center_x + 2] = 1
    cells[center_y + 1][center_x + 2] = 1
}

get_alive_nbrs :: proc(cs : ^[MAP_SIZE][MAP_SIZE]u8, index_x, index_y : int) -> (alive_nbrs : u8) {
    start_y := index_y > 0 ? index_y - 1 : index_y
    end_y := index_y < MAP_SIZE - 1 ? index_y + 2 : index_y + 1
    start_x := index_x > 0 ? index_x - 1 : index_x
    end_x := index_x < MAP_SIZE - 1 ? index_x + 2 : index_x + 1
    for &subslice in cs[start_y : end_y] {
        for val in subslice[start_x : end_x] {
            alive_nbrs += val
        }
    }
    alive_nbrs -= cs[index_y][index_x]
    return alive_nbrs
}

process_next_generation :: proc(cs : ^[MAP_SIZE][MAP_SIZE]u8, buf : ^[MAP_SIZE][MAP_SIZE]u8) {
    for y in 0..<MAP_SIZE {
        for x in 0..<MAP_SIZE {
            cell := cs[y][x]
            alive_neighbors := get_alive_nbrs(cs, x, y)
            if cell == 1 && (alive_neighbors < 2 || alive_neighbors > 3) {
                buf[y][x] = 0
            }
            else if cell == 1 && (alive_neighbors == 2 || alive_neighbors == 3) {
                buf[y][x] = 1
            }
            else if cell == 0 && alive_neighbors == 3 {
                buf[y][x] = 1
            }
        }
    }
}

update_greetings_screen :: proc(stay_in_greetings_screen : ^bool) {
    for key in rl.KeyboardKey {
        if rl.IsKeyPressed(key) {
            stay_in_greetings_screen^ = false
        }
    }
    for key in rl.MouseButton {
        if rl.IsMouseButtonPressed(key) {
            stay_in_greetings_screen^ = false
        }
    }
}

restart :: proc(cells : ^[MAP_SIZE][MAP_SIZE]u8, is_paused : ^bool) {
    for y in 0..<MAP_SIZE {
        for x in 0..<MAP_SIZE {
            cells[y][x] = 0
        }
    }
    place_glider(cells, 4, 4)
    is_paused^ = true
}

draw_text_with_shadow :: #force_inline proc(text: cstring, posx, posy: i32) {
    rl.DrawText(text, posx + 1, posy, DEFAULT_FONT_SIZE, DEFAULT_TEXT_SHADOW_COLOR)
    rl.DrawText(text, posx, posy, DEFAULT_FONT_SIZE, DEFAULT_TEXT_COLOR)
}

draw_greetings_screen :: proc() {
    text_start_x_pos : i32 = 50
    text_start_y_pos : i32 = 50
    margin : i32 = 5
    how_to_start_x_pos : i32 = 500
    rl.BeginDrawing()
    rl.ClearBackground(BG_COLOR)

    draw_text_with_shadow("DRAG MAP ->", text_start_x_pos, text_start_y_pos)
    draw_text_with_shadow("hold \"MMB\" and drag mouse", how_to_start_x_pos, text_start_y_pos)

    y := text_start_y_pos + DEFAULT_FONT_SIZE + margin
    draw_text_with_shadow("EXIT ->", text_start_x_pos, y)
    draw_text_with_shadow("\"ESC\" or close window", how_to_start_x_pos, y)

    y = text_start_y_pos + (DEFAULT_FONT_SIZE + margin) * 2
    draw_text_with_shadow("RESTART ->", text_start_x_pos, y)
    draw_text_with_shadow("\"R\"", how_to_start_x_pos, y)

    y = text_start_y_pos + (DEFAULT_FONT_SIZE + margin) * 3
    draw_text_with_shadow("DRAW/PLACE FIGURES ->", text_start_x_pos, y)
    draw_text_with_shadow("\"LMB\"", how_to_start_x_pos, y)

    y = text_start_y_pos + (DEFAULT_FONT_SIZE + margin) * 4
    draw_text_with_shadow("SELECT PENCIL DRAW TOOL ->", text_start_x_pos, y)
    draw_text_with_shadow("\"1\"", how_to_start_x_pos, y)

    y = text_start_y_pos + (DEFAULT_FONT_SIZE + margin) * 5
    draw_text_with_shadow("SELECT GLIDER PLACEMENT TOOL ->", text_start_x_pos, y)
    draw_text_with_shadow("\"2\"", how_to_start_x_pos, y)

    text : cstring = "PRESS ANY KEY TO CONTINUE"
    text_width := rl.MeasureText(text, DEFAULT_FONT_SIZE)
    draw_text_with_shadow(text, (WIDTH - text_width) / 2, HEIGHT - 50)

    rl.EndDrawing()
}