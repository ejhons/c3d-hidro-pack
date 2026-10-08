// ligacoes.dcl - dialogo da tabela de objetos e ligacoes (plugins/objetos_tabela.lsp)
// Somente ASCII, de proposito (sem problemas de codificacao).

ligacoes_dialog : dialog {
  label = "HYDRO - Objetos hidraulicos e ligacoes";

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

  : text { key = "t_cols"; width = 100; }

  : list_box {
    key = "lst";
    width = 100;
    height = 11;
    fixed_width_font = true;
    tabs = "16 30 38 54 60";
    tab_truncate = true;
  }

  : text { label = "Detalhes, jusante e arvore de afluentes do objeto selecionado:"; }

  : list_box {
    key = "det";
    width = 100;
    height = 13;
    fixed_width_font = true;
  }

  spacer;

  : row {
    alignment = centered;
    : button { key = "ir";       label = "&Ir para";       width = 12; fixed_width = true; }
    : button { key = "ligar";    label = "&Ligar...";      width = 12; fixed_width = true; }
    : button { key = "desligar"; label = "&Desligar";      width = 12; fixed_width = true; }
    : button { key = "editar";   label = "&Editar";        width = 12; fixed_width = true; }
    : button { key = "calcular"; label = "Ca&lcular...";   width = 14; fixed_width = true; }
  }

  : row {
    alignment = centered;
    : button { key = "validar";   label = "&Validar ligacoes"; width = 18; fixed_width = true; }
    : button { key = "csv";       label = "Exportar &CSV";     width = 16; fixed_width = true; }
    : button { key = "reindexar"; label = "Rein&dexar";        width = 12; fixed_width = true; }
    : button {
      key = "cancel";
      label = "Fechar";
      is_cancel = true;
      width = 12;
      fixed_width = true;
    }
  }
}
