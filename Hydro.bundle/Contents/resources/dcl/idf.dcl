idf_dialog : dialog {

    label = "Equa��o IDF";

    : column {
        : boxed_column {
            label = "Equacao";
            : image_button {
                key = "formula";
                width = 50;
                height = 10;
                fixed_width = true;
                fixed_height = true;
                alignment = centered;
            }
        }
        spacer;

        : row {
            : boxed_column {
                label = "Par�metros";
                : row {
                    : text {
                        label = "k =";
                        width = 6;
                    }
                    : text {
                        key = "k_val";
                        width = 12;
                    }
                }
				: row {
					: text {
						label = "s =";
						width = 6;
					}
					: text {
						key = "s_val";
						width = 12;
					}
				}
				: row {
					: text {
						label = "p =";
						width = 6;
					}
					: text {
						key = "p_val";
						width = 12;
					}
				}
			}
            : boxed_column {
                : row {
                    : text {
                        label = "a =";
                        width = 6;
                    }
                    : text {
                        key = "a_val";
                        width = 12;
                    }
                }
                : row {
                    : text {
                        label = "b =";
                        width = 6;
                    }
                    : text {
                        key = "b_val";
                        width = 12;
                    }
                }
                : row {
                    : text {
                        label = "c =";
                        width = 6;
                    }
                    : text {
                        key = "c_val";
                        width = 12;
                    }
                }
            }

            : boxed_column {
                label = "Variaveis (editaveis)";
                : edit_box {
                    key = "tr_val";
                    label = "tr (anos) =";
                    edit_width = 10;
                }
                : edit_box {
                    key = "tc_val";
                    label = "tc (min) =";
                    edit_width = 10;
                }
                : edit_box {
                    key = "dur_val";
                    label = "dur. (min) =";
                    edit_width = 10;
                }
                : toggle {
                    key = "dur_igual";
                    label = "Duracao = &tc";
                }
            }
        }

        spacer;

        : boxed_column {

            label = "Substituicao";
			children_alignment = top;

            : text {
                key = "substituicao_1";
                width = 65;
                alignment = centered;
				fixed_height = true;
				vertical_margin = none;
            }
            : text {
                value = "      ------------------------------------------------";
                width = 65;
                alignment = centered;
				fixed_height = true;
				vertical_margin = none;
            }
            : text {
                key = "substituicao_2";
                width = 65;
                alignment = centered;
				fixed_height = true;
				vertical_margin = none;
            }
            : text {
                value = " ";
                width = 65;
                alignment = centered;
				fixed_height = true;
				vertical_margin = none;
            }

        }

        spacer;

        : boxed_column {

            label = "Resultado";

            : text {
                key = "resultado";
                width = 30;
                alignment = centered;
            }

        }

        spacer;

        : row {

            spacer;

            : button {
                key = "accept";
                label = "&Calcular";
                is_default = true;
                width = 12;
            }

            : button {
                key = "cancel";
                label = "Fechar";
                is_cancel = true;
                width = 12;
            }

            spacer;

        }

    }

}