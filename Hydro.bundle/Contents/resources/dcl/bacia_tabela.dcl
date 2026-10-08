// bacia_tabela.dcl - dialogo da tabela de bacias (plugins/bacia_tabela.lsp)
// Somente ASCII, de proposito (sem problemas de codificacao).

bacias_dialog : dialog {
  label = "HYDRO - Bacias do desenho";

  : row {
    : edit_box { key = "filtro"; label = "Fi&ltro:"; edit_width = 28; }
    : button {
      key = "filtrar";
      label = "&Aplicar";
      width = 10;
      fixed_width = true;
      is_default = true;
    }
    : text { key = "titulo"; width = 30; }
  }

  : text { key = "t_cols"; width = 106; }

  : list_box {
    key = "lst";
    width = 106;
    height = 12;
    fixed_width_font = true;
    tabs = "14 21 31 40 49 58 74 80 86";
    tab_truncate = true;
  }

  : text { label = "Detalhes da bacia selecionada:"; }

  : list_box {
    key = "det";
    width = 106;
    height = 12;
    fixed_width_font = true;
  }

  spacer;

  : row {
    alignment = centered;
    : button { key = "ir";      label = "&Ir para";            width = 14; fixed_width = true; }
    : button { key = "hid";     label = "&Hidrogramas";        width = 16; fixed_width = true; }
    : button { key = "texto";   label = "&Texto no desenho";   width = 20; fixed_width = true; }
    : button { key = "editar";  label = "E&ditar cadastro";    width = 18; fixed_width = true; }
  }

  : row {
    alignment = centered;
    : button { key = "csv";       label = "Exportar &CSV";       width = 16; fixed_width = true; }
    : button { key = "remover";   label = "&Remover cadastro";   width = 20; fixed_width = true; }
    : button { key = "reindexar"; label = "Rein&dexar";          width = 14; fixed_width = true; }
    : button {
      key = "cancel";
      label = "Fechar";
      is_cancel = true;
      width = 14;
      fixed_width = true;
    }
  }
}
