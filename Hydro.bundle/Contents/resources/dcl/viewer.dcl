// viewer.dcl - dialogo do visualizador HYDRO (viewer.lsp)

view_dialog : dialog {
  label = "HYDRO - Dados persistidos";

  : radio_row {
    : radio_button { key = "modo_cfg"; label = "&Configuracoes (DB)"; }
    : radio_button { key = "modo_ent"; label = "&Entidades com dados (XData)"; }
  }

  : row {
    : edit_box { key = "filtro"; label = "Fi&ltro:"; edit_width = 30; }
    : button { key = "filtrar"; label = "&Aplicar"; width = 10; fixed_width = true; is_default = true; }
    : text { key = "titulo"; label = ""; width = 30; }
  }

  : list_box {
    key = "lista";
    width = 100;
    height = 14;
    fixed_width_font = true;
    tabs = "30 62";
    tab_truncate = true;
  }

  : text { label = "Detalhes:"; }

  : list_box {
    key = "detalhe";
    width = 100;
    height = 8;
    fixed_width_font = true;
  }

  : row {
    : button { key = "ir"; label = "&Ir para entidade"; width = 20; fixed_width = true; }
    : button { key = "csv"; label = "Exportar &CSV"; width = 18; fixed_width = true; }
    : spacer { width = 40; }
    : button { key = "fechar"; label = "Fechar"; width = 12; fixed_width = true; is_cancel = true; }
  }
}
